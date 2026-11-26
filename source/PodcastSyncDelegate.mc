import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Media;
import Toybox.PersistedContent;

// The running sync, if any. Global rather than a delegate field: the system
// can call onStopSync on a different delegate instance than onStartSync.
var gSyncJob = null;

// Sync started by the user from the app.
function startManualSync() as Void {
    Log.line("sync", "manual sync requested");
    Media.startSync();
}

// Invoked by the system when the user starts a sync (normally over Wi-Fi).
//
// Uses the older Media sync API (Media.SyncDelegate, Media.notifySync*,
// Media.startSync), deprecated in favour of the Communications versions.
// With the Communications API, syncs the watch starts on the charger showed
// no progress and stayed "syncing" after notifySyncComplete; audio content
// providers predate that API, so the firmware may only follow the Media one
// there. Deprecated, not removed: still in SDK 9.3 for all listed products.
class PodcastSyncDelegate extends Media.SyncDelegate {

    function initialize() {
        SyncDelegate.initialize();
    }

    function onStartSync() as Void {
        Log.line("sync", "onStartSync");
        if (gSyncJob != null) {
            gSyncJob.cancel();   // leftover from a sync that never finished
        }
        gSyncJob = new SyncJob();
        gSyncJob.start();
    }

    // Asked by the watch before every sync; when false, the sync doesn't
    // run. There is no cheap way to know whether Up Next changed, so always
    // sync.
    function isSyncNeeded() as Boolean {
        Log.line("sync", "isSyncNeeded -> true");
        return true;
    }

    function onStopSync() as Void {
        Log.line("sync", "onStopSync");
        if (gSyncJob != null) {
            gSyncJob.cancel();
            gSyncJob = null;
        }
        Communications.cancelAllRequests();
        Media.notifySyncComplete("Sync cancelled");
        Log.line("sync", "notifySyncComplete(Sync cancelled)");
    }
}

// Sync steps, chained through web request callbacks:
//   login (if needed) -> push queued progress -> fetch Up Next
//   -> delete episodes no longer queued -> download new ones -> done
class SyncJob {

    hidden var _api;
    hidden var _cancelled = false;
    hidden var _reloggedIn = false;
    hidden var _afterLogin;      // Method to resume after (re)login

    hidden var _pendingKeys;
    hidden var _pendingIdx = 0;

    hidden var _remote;          // Up Next episodes from server
    hidden var _remoteIdx = 0;
    hidden var _old;             // episodes stored before this sync
    hidden var _max = 5;

    hidden var _targets;         // episodes to keep, in order
    hidden var _toDownload;      // indices into _targets
    hidden var _dlIdx = 0;
    hidden var _failed = 0;
    hidden var _speed = 100;     // wanted speed in percent (settings)
    hidden var _kbps = 64;       // wanted bitrate (settings)
    hidden var _viaService = false;  // current download goes through the speed service
    hidden var _serviceError = null; // last speed server error code this sync
    hidden var _loggedProgress = -10;

    function initialize() {
        _api = new PocketCastsApi();
    }

    function start() {
        log("sync start, version " + APP_VERSION);
        ensureLogin(method(:pushProgress));
    }

    function cancel() {
        _cancelled = true;
    }

    // ---- login ---------------------------------------------------------

    hidden function ensureLogin(next) {
        if (EpisodeStore.getToken() != null) {
            next.invoke();
            return;
        }
        var email = Application.Properties.getValue("email");
        var password = Application.Properties.getValue("password");
        if (email == null || password == null || email.length() == 0 || password.length() == 0) {
            fail("Enter your Pocket Casts email and password in the app settings (Garmin Connect)");
            return;
        }
        _afterLogin = next;
        _api.login(email, password, method(:onLogin));
    }

    function onLogin(code as Number, data) as Void {
        if (_cancelled) { return; }
        log("login -> " + code);
        if (code == 200 && data instanceof Dictionary && data["token"] != null) {
            EpisodeStore.setToken(data["token"]);
            _afterLogin.invoke();
        } else {
            fail(loginError(code, data));
        }
    }

    // Human-readable reason for a failed login.
    hidden function loginError(code, data) {
        if (code < 0) {
            return "Can't reach Pocket Casts. Check the watch's Wi-Fi connection (error " + code + ")";
        }
        var serverMsg = (data instanceof Dictionary) ? data["errorMessage"] : null;
        if (code == 400 || code == 401 || code == 403) {
            return "Pocket Casts login failed: "
                + (serverMsg != null ? serverMsg : "wrong email or password")
                + ". Check the app settings in Garmin Connect";
        }
        return "Pocket Casts login failed (HTTP " + code + ")";
    }

    // On 401, drop the token and log in again once, then retry `retry`.
    hidden function handleUnauthorized(code, retry) {
        if (code != 401 || _reloggedIn) {
            return false;
        }
        _reloggedIn = true;
        EpisodeStore.clearToken();
        ensureLogin(retry);
        return true;
    }

    // ---- push playback progress ----------------------------------------

    function pushProgress() as Void {
        _pendingKeys = EpisodeStore.getPending().keys();
        _pendingIdx = 0;
        pushNext();
    }

    function pushNext() as Void {
        if (_cancelled) { return; }
        if (_pendingIdx >= _pendingKeys.size()) {
            fetchUpNext();
            return;
        }
        var uuid = _pendingKeys[_pendingIdx];
        var p = EpisodeStore.getPending()[uuid];
        if (p == null) {
            _pendingIdx++;
            pushNext();
            return;
        }
        _api.updateEpisode(uuid, p["podcast"], p["position"], p["status"], method(:onPushed));
    }

    function onPushed(code as Number, data) as Void {
        if (_cancelled) { return; }
        log("update_episode " + _pendingKeys[_pendingIdx] + " -> " + code);
        if (handleUnauthorized(code, method(:pushNext))) { return; }
        if (code == 200) {
            EpisodeStore.removePending(_pendingKeys[_pendingIdx]);
        }
        // On other errors keep the update queued for the next sync.
        _pendingIdx++;
        pushNext();
    }

    // ---- Up Next -------------------------------------------------------

    function fetchUpNext() as Void {
        if (_cancelled) { return; }
        progress(5);
        _api.upNext(method(:onUpNext));
    }

    function onUpNext(code as Number, data) as Void {
        if (_cancelled) { return; }
        log("up_next -> " + code);
        if (handleUnauthorized(code, method(:fetchUpNext))) { return; }
        if (code != 200 || !(data instanceof Dictionary)) {
            // -402 = response too large for watch memory
            fail(code < 0
                ? "Can't reach Pocket Casts. Check the watch's Wi-Fi connection (error " + code + ")"
                : "Couldn't load Up Next (HTTP " + code + ")");
            return;
        }
        _remote = data["episodes"];
        if (_remote == null) { _remote = []; }
        _max = Application.Properties.getValue("episodeCount");
        if (_max == null || _max < 1) { _max = 5; }
        _speed = Application.Properties.getValue("playSpeed");
        if (_speed == null || _speed < 50 || _speed > 300) { _speed = 100; }
        _kbps = Application.Properties.getValue("bitrate");
        if (_kbps == null || _kbps < 32 || _kbps > 128) { _kbps = 64; }
        _old = EpisodeStore.getEpisodes();
        _targets = [];
        _remoteIdx = 0;
        fetchDetailNext();
    }

    // Up Next has no play state, so fetch it per episode (/user/episode,
    // ~1 KB each) until we have enough unplayed episodes.
    function fetchDetailNext() as Void {
        if (_cancelled) { return; }
        if (_targets.size() >= _max || _remoteIdx >= _remote.size()) {
            reconcile();
            return;
        }
        progress(5 + (5 * _targets.size()) / _max);
        var e = _remote[_remoteIdx];
        _api.episode(e["uuid"], e["podcast"], method(:onDetail));
    }

    function onDetail(code as Number, data) as Void {
        if (_cancelled) { return; }
        if (handleUnauthorized(code, method(:fetchDetailNext))) { return; }
        var e = _remote[_remoteIdx];
        _remoteIdx++;
        log("episode " + e["title"] + " -> " + code
            + (data instanceof Dictionary ? " status=" + data["playingStatus"] + " pos=" + data["playedUpTo"] : ""));

        var detail = (code == 200 && data instanceof Dictionary) ? data : null;
        if (detail != null && detail["playingStatus"] == EpisodeStore.STATUS_PLAYED) {
            fetchDetailNext();
            return;
        }

        var ep = EpisodeStore.findByUuid(_old, e["uuid"]);
        if (ep == null) {
            ep = {
                "uuid" => e["uuid"],
                "podcast" => e["podcast"],
                "title" => e["title"],
                "url" => e["url"],
                "ref" => null,
                "pos" => 0,
                "done" => false
            };
        }
        ep["done"] = false;
        if (detail != null) {
            // Pending local progress was pushed first, so the server is current.
            if (detail["playedUpTo"] != null) { ep["pos"] = detail["playedUpTo"].toNumber(); }
            ep["type"] = detail["fileType"];
        }
        _targets.add(ep);
        fetchDetailNext();
    }

    hidden function reconcile() {
        // Free space: drop cached audio for episodes that left the queue or were played.
        for (var i = 0; i < _old.size(); i++) {
            if (EpisodeStore.findByUuid(_targets, _old[i]["uuid"]) == null) {
                // "oldRef" is left over if a re-download was interrupted.
                var refs = [_old[i]["ref"], _old[i]["oldRef"]];
                for (var j = 0; j < refs.size(); j++) {
                    if (refs[j] != null) {
                        Media.deleteCachedItem(new Media.ContentRef(refs[j], Media.CONTENT_TYPE_AUDIO));
                    }
                }
            }
        }
        // Files made with other speed/bitrate settings are downloaded again.
        // The old file stays playable ("oldRef") until the new one arrives.
        for (var i = 0; i < _targets.size(); i++) {
            var ep = _targets[i];
            if (ep["ref"] != null && needsNewFile(ep)) {
                log("settings changed, re-download " + ep["title"]);
                ep["oldRef"] = ep["ref"];
                ep["ref"] = null;
            }
        }
        EpisodeStore.setEpisodes(_targets);
        _old = null;
        _remote = null;

        _toDownload = [];
        for (var i = 0; i < _targets.size(); i++) {
            if (_targets[i]["ref"] == null) { _toDownload.add(i); }
        }
        _dlIdx = 0;
        downloadNext();
    }

    // ---- downloads -----------------------------------------------------

    hidden function downloadNext() {
        if (_cancelled) { return; }
        if (_dlIdx >= _toDownload.size()) {
            finish();
            return;
        }
        var ep = _targets[_toDownload[_dlIdx]];
        _viaService = _api.hasAudioService();
        startDownload(ep);
    }

    // URL of the episode downloaded after the current one, for the speed
    // service to convert while this one downloads.
    hidden function nextUrl() {
        var i = _dlIdx + 1;
        return i < _toDownload.size() ? _targets[_toDownload[i]]["url"] : null;
    }

    hidden function startDownload(ep) {
        if (_viaService) {
            log("download " + ep["title"] + " via service at " + _speed + "% " + _kbps + " kbps");
            _api.downloadConverted(ep["url"], nextUrl(), _speed, _kbps,
                method(:onDownloadProgress), method(:onDownloaded));
        } else {
            log("download " + ep["title"] + " (original)");
            _api.downloadOriginal(ep["url"], encodingFor(ep),
                method(:onDownloadProgress), method(:onDownloaded));
        }
    }

    // A file must be replaced if it doesn't match the current settings.
    // Originals downloaded as a fallback (service unreachable) are retried
    // through the service on each sync, while it's configured.
    hidden function needsNewFile(ep) {
        if (!_api.hasAudioService()) {
            return false;   // no service: keep whatever we have
        }
        return EpisodeStore.speedOf(ep) != _speed || ep["kbps"] != _kbps;
    }

    function onDownloadProgress(bytes as Number, total as Number?) as Void {
        var frac = (total == null || total == 0) ? 0.0 : bytes.toFloat() / total;
        var overall = (_dlIdx + frac) / _toDownload.size();
        progress((10 + 90 * overall).toNumber());
    }

    function onDownloaded(code as Number, data as Null or ByteArray or Dictionary or String or PersistedContent.Iterator) as Void {
        if (_cancelled) { return; }
        log("download -> " + code);
        if (code == Communications.REQUEST_CANCELLED) {
            // Cancelled by the system without onStopSync (which would have
            // set _cancelled first). Don't fall back to the original; end
            // the sync, or the watch keeps waiting for it.
            restoreOld(_targets[_toDownload[_dlIdx]]);
            fail("Sync was interrupted. Try again");
            return;
        }
        var ep = _targets[_toDownload[_dlIdx]];
        if (code == 200 && data != null) {
            ep["ref"] = (data as Media.ContentRef).getId();
            ep["speed"] = _viaService ? _speed : 100;
            ep["kbps"] = _viaService ? _kbps : null;
            if (ep["oldRef"] != null) {
                Media.deleteCachedItem(new Media.ContentRef(ep["oldRef"], Media.CONTENT_TYPE_AUDIO));
                ep.remove("oldRef");
            }
            EpisodeStore.setEpisodes(_targets);
        } else if (_viaService) {
            // Service unreachable or failed: fall back to the original file.
            log("service failed (" + code + "), falling back to original");
            _serviceError = code;
            _viaService = false;
            if (ep["oldRef"] != null) {
                // An older file exists; keep it rather than downloading the original.
                restoreOld(ep);
                _dlIdx++;
                downloadNext();
            } else {
                startDownload(ep);
            }
            return;
        } else {
            restoreOld(ep);
            _failed++;
        }
        _dlIdx++;
        downloadNext();
    }

    // Re-download failed: keep playing the previous file.
    hidden function restoreOld(ep) {
        if (ep["oldRef"] != null) {
            ep["ref"] = ep["oldRef"];
            ep.remove("oldRef");
            EpisodeStore.setEpisodes(_targets);
        }
    }

    hidden function encodingFor(ep) {
        var type = ep["type"];
        if (type != null) {
            type = type.toLower();
            if (type.find("mp4") != null || type.find("m4a") != null || type.find("aac") != null) {
                return Media.ENCODING_M4A;
            }
            if (type.find("mpeg") != null || type.find("mp3") != null) {
                return Media.ENCODING_MP3;
            }
        }
        var u = ep["url"].toLower();
        if (u.find(".m4a") != null || u.find(".mp4") != null || u.find(".aac") != null) {
            return Media.ENCODING_M4A;
        }
        return Media.ENCODING_MP3;
    }

    // ---- completion ----------------------------------------------------

    hidden function finish() {
        log("sync done, failed=" + _failed);
        progress(100);
        var onWatch = 0;
        for (var i = 0; i < _targets.size(); i++) {
            if (_targets[i]["ref"] != null) { onWatch++; }
        }
        EpisodeStore.setLastResult({
            "downloaded" => _toDownload.size() - _failed,
            "failed" => _failed,
            "onWatch" => onWatch,
            "queued" => _targets.size(),
            "serviceError" => _serviceError
        });
        if (_failed > 0) {
            var msg = "Downloaded " + (_toDownload.size() - _failed) + " of "
                + _toDownload.size() + " episodes, " + _failed + " failed";
            EpisodeStore.setLastError(msg);
            complete(msg);
        } else {
            EpisodeStore.setLastError(null);
            complete(null);
        }
    }

    hidden function fail(message) {
        log("sync failed: " + message);
        EpisodeStore.setLastError(message);
        complete(message);
    }

    hidden function log(msg) {
        Log.line("sync", msg);
    }

    // Reports progress to the watch; logged in steps of 10 %.
    hidden function progress(percent) {
        if (percent / 10 != _loggedProgress / 10) {
            _loggedProgress = percent;
            log("progress " + percent + "%");
        }
        Media.notifySyncProgress(percent);
    }

    hidden function complete(message) {
        Media.notifySyncComplete(message);
        log("notifySyncComplete(" + (message == null ? "null" : message) + ")");
    }
}
