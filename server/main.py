"""Podcast speed service for the Podcast Sync watch app.

The watch asks for an episode at a given speed; this service downloads the
original audio, speeds it up with ffmpeg (pitch preserved), re-encodes it as
mono MP3 for speech, and returns it.

    GET /audio?url=<original audio URL>&speed=1.5[&kbps=64][&next=<URL>]
    Header: X-Api-Key: <API_KEY>   (or &key=<API_KEY> in the query)

`next` is the episode the watch will ask for after this one. It is converted
in the background (same speed and bitrate) while the watch downloads this one,
so the next request is answered from the cache. Background work needs CPU
outside requests: deploy with --no-cpu-throttling.

With CACHE_BUCKET set (recommended on Cloud Run), the result is stored in
Cloud Storage and the response is a 302 redirect to a short-lived signed URL.
That avoids Cloud Run's 32 MiB response limit, gives the watch a
Content-Length for its progress bar, and makes repeat requests instant.
Without CACHE_BUCKET (local testing) files are cached in CACHE_DIR and
returned directly.

Requests for a file that is already being converted wait for that conversion
instead of starting another one. The watch retries a request it has waited on
for about 45 s, and a `next` conversion can still be running when the watch
asks for that episode.

Environment:
    API_KEY        required; shared secret, also set in the watch app settings
    CACHE_BUCKET   optional; Cloud Storage bucket name for converted files
    CACHE_DIR      local cache without CACHE_BUCKET (default /tmp/podcast-speed)
    PORT           set by Cloud Run (default 8080)
"""

import hashlib
import hmac
import logging
import os
import shutil
import subprocess
import tempfile
import threading
import time
from datetime import timedelta
from urllib.parse import urlparse

from flask import Flask, abort, jsonify, redirect, request, send_file

API_KEY = os.environ.get("API_KEY", "")
CACHE_BUCKET = os.environ.get("CACHE_BUCKET", "")
CACHE_DIR = os.environ.get("CACHE_DIR", "/tmp/podcast-speed")
LOCAL_CACHE_MAX_AGE_S = 24 * 3600

MIN_SPEED, MAX_SPEED = 0.5, 3.0
MIN_KBPS, MAX_KBPS, DEFAULT_KBPS = 32, 128, 64
FFMPEG_TIMEOUT_S = 840          # keep under the Cloud Run request timeout (900 s)
SIGNED_URL_TTL = timedelta(hours=1)
USER_AGENT = "PodcastSpeed/1.0"  # some podcast hosts reject ffmpeg's default UA

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
log = logging.getLogger("speed")

_bucket = None

# Conversions in progress in this process: cache name -> threading.Event,
# set when the conversion has finished (successfully or not).
_inflight = {}
_inflight_lock = threading.Lock()


def bucket():
    """Cloud Storage bucket, created lazily so local runs don't need the library."""
    global _bucket
    if _bucket is None:
        from google.cloud import storage
        _bucket = storage.Client().bucket(CACHE_BUCKET)
    return _bucket


def signed_url(blob):
    """V4 signed URL. On Cloud Run there is no private key file, so signing goes
    through the IAM signBlob API using the service account's access token
    (the account needs roles/iam.serviceAccountTokenCreator on itself)."""
    import google.auth
    import google.auth.transport.requests

    creds, _ = google.auth.default()
    creds.refresh(google.auth.transport.requests.Request())
    return blob.generate_signed_url(
        version="v4",
        expiration=SIGNED_URL_TTL,
        method="GET",
        service_account_email=creds.service_account_email,
        access_token=creds.token,
    )


def check_key():
    if not API_KEY:
        abort(500, "API_KEY is not configured")
    given = request.headers.get("X-Api-Key") or request.args.get("key", "")
    if not hmac.compare_digest(given.encode(), API_KEY.encode()):
        abort(401)


def parse_args():
    url = request.args.get("url", "")
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        abort(400, "url must be an http(s) URL")
    try:
        speed = round(float(request.args.get("speed", "1.0")), 2)
        kbps = int(request.args.get("kbps", DEFAULT_KBPS))
    except ValueError:
        abort(400, "speed and kbps must be numbers")
    if not MIN_SPEED <= speed <= MAX_SPEED:
        abort(400, f"speed must be between {MIN_SPEED} and {MAX_SPEED}")
    kbps = max(MIN_KBPS, min(MAX_KBPS, kbps))
    return url, speed, kbps


def parse_next():
    """Optional `next` URL; ignored if it isn't a valid http(s) URL."""
    url = request.args.get("next", "")
    parsed = urlparse(url)
    return url if parsed.scheme in ("http", "https") and parsed.netloc else None


def convert_in_background(url, speed, kbps):
    def run():
        try:
            ensure_converted(url, speed, kbps, cache_name(url, speed, kbps))
        except Exception as e:  # abort() raises too; nobody is waiting for the answer
            log.warning("background conversion of %s failed: %s", url, e)
    threading.Thread(target=run, daemon=True).start()


def convert(url, speed, kbps, out_path):
    """Stream the original straight into ffmpeg, so conversion overlaps the
    download. Only the first audio stream is kept (drops cover art); tags such
    as title are kept, because the watch reads them for its display."""
    cmd = [
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
        "-protocol_whitelist", "http,https,tcp,tls,crypto",
        "-user_agent", USER_AGENT,
        "-i", url,
        "-map", "0:a:0", "-map_metadata", "0",
        # Mono 22.05 kHz before atempo: plenty for speech, and halves the work
        # of both atempo and the encoder (about 2x faster overall). Higher
        # bitrates keep 44.1 kHz, otherwise the extra bits buy no quality.
        "-af", f"aformat=channel_layouts=mono:sample_rates={22050 if kbps < 96 else 44100},atempo={speed}",
        # LAME quality 7: noticeably faster, little audible difference for voice.
        "-c:a", "libmp3lame", "-b:a", f"{kbps}k", "-compression_level", "7",
        "-id3v2_version", "3",
        "-y", out_path,
    ]
    started = time.monotonic()
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=FFMPEG_TIMEOUT_S)
    if result.returncode != 0:
        log.error("ffmpeg failed for %s: %s", url, result.stderr[-2000:])
        abort(502, "could not convert the episode")
    log.info("converted %s at %sx in %.1f s (%d bytes)", url, speed, time.monotonic() - started,
             os.path.getsize(out_path))


def cache_name(url, speed, kbps):
    return "audio/" + hashlib.sha256(f"{url}|{speed}|{kbps}".encode()).hexdigest() + ".mp3"


def local_path(name):
    return os.path.join(CACHE_DIR, os.path.basename(name))


def is_cached(name):
    if CACHE_BUCKET:
        return bucket().blob(name).exists()
    return os.path.exists(local_path(name))


def store(name, path):
    if CACHE_BUCKET:
        bucket().blob(name).upload_from_filename(path, content_type="audio/mpeg")
        return
    os.makedirs(CACHE_DIR, exist_ok=True)
    # Local cache: drop files older than a day so it doesn't grow forever.
    for f in os.listdir(CACHE_DIR):
        p = os.path.join(CACHE_DIR, f)
        if time.time() - os.path.getmtime(p) > LOCAL_CACHE_MAX_AGE_S:
            os.remove(p)
    shutil.move(path, local_path(name))


def ensure_converted(url, speed, kbps, name):
    """Make sure the converted file is in the cache. If another request is
    already converting it, wait for that instead of converting it twice."""
    if is_cached(name):
        log.info("cache hit %s", name)
        return
    with _inflight_lock:
        done = _inflight.get(name)
        owner = done is None
        if owner:
            done = threading.Event()
            _inflight[name] = done
    if not owner:
        log.info("waiting for conversion in progress %s", name)
        done.wait(FFMPEG_TIMEOUT_S + 60)
        if not is_cached(name):
            abort(502, "could not convert the episode")
        return
    try:
        if is_cached(name):   # finished between the first check and the lock
            return
        with tempfile.TemporaryDirectory() as tmp:  # /tmp on Cloud Run is in memory
            out_path = os.path.join(tmp, "out.mp3")
            convert(url, speed, kbps, out_path)
            store(name, out_path)
    finally:
        with _inflight_lock:
            del _inflight[name]
        done.set()


@app.get("/")
def health():
    return "ok"


@app.get("/audio")
def audio():
    check_key()
    url, speed, kbps = parse_args()
    nxt = parse_next()
    if nxt and nxt != url:
        convert_in_background(nxt, speed, kbps)
    name = cache_name(url, speed, kbps)
    ensure_converted(url, speed, kbps, name)
    if CACHE_BUCKET:
        return redirect(signed_url(bucket().blob(name)), code=302)
    return send_file(local_path(name), mimetype="audio/mpeg", download_name="episode.mp3")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
