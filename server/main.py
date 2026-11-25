"""Podcast speed service for the Podcast Sync watch app.

The watch asks for an episode at a given speed; this service downloads the
original audio, speeds it up with ffmpeg (pitch preserved), re-encodes it as
mono MP3 for speech, and returns it.

    GET /audio?url=<original audio URL>&speed=1.5[&kbps=64]
    Header: X-Api-Key: <API_KEY>   (or &key=<API_KEY> in the query)

With CACHE_BUCKET set (recommended on Cloud Run), the result is stored in
Cloud Storage and the response is a 302 redirect to a short-lived signed URL.
That avoids Cloud Run's 32 MiB response limit, gives the watch a
Content-Length for its progress bar, and makes repeat requests instant.
Without CACHE_BUCKET (local testing) the file is returned directly.

Environment:
    API_KEY        required; shared secret, also set in the watch app settings
    CACHE_BUCKET   optional; Cloud Storage bucket name for converted files
    PORT           set by Cloud Run (default 8080)
"""

import hashlib
import hmac
import logging
import os
import subprocess
import tempfile
import time
from datetime import timedelta
from urllib.parse import urlparse

from flask import Flask, abort, redirect, request, send_file

API_KEY = os.environ.get("API_KEY", "")
CACHE_BUCKET = os.environ.get("CACHE_BUCKET", "")

MIN_SPEED, MAX_SPEED = 0.5, 3.0
MIN_KBPS, MAX_KBPS, DEFAULT_KBPS = 32, 128, 64
FFMPEG_TIMEOUT_S = 840          # keep under the Cloud Run request timeout (900 s)
SIGNED_URL_TTL = timedelta(hours=1)
USER_AGENT = "PodcastSpeed/1.0"  # some podcast hosts reject ffmpeg's default UA

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
log = logging.getLogger("speed")

_bucket = None


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


@app.get("/")
def health():
    return "ok"


@app.get("/audio")
def audio():
    check_key()
    url, speed, kbps = parse_args()
    name = "audio/" + hashlib.sha256(f"{url}|{speed}|{kbps}".encode()).hexdigest() + ".mp3"

    if CACHE_BUCKET:
        blob = bucket().blob(name)
        if blob.exists():
            log.info("cache hit %s", name)
            return redirect(signed_url(blob), code=302)

    with tempfile.TemporaryDirectory() as tmp:  # /tmp on Cloud Run is in memory
        out_path = os.path.join(tmp, "out.mp3")
        convert(url, speed, kbps, out_path)
        if CACHE_BUCKET:
            blob.upload_from_filename(out_path, content_type="audio/mpeg")
            return redirect(signed_url(blob), code=302)
        # Local testing: send the file itself. Read it into memory first,
        # because the temporary directory is deleted when this block exits.
        with open(out_path, "rb") as f:
            data = f.read()
    from io import BytesIO
    return send_file(BytesIO(data), mimetype="audio/mpeg", download_name="episode.mp3")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
