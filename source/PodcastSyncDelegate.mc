import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Media;
import Toybox.PersistedContent;
import Toybox.System;

// Invoked by the system when the user starts a sync (normally over Wi-Fi).
class PodcastSyncDelegate extends Communications.SyncDelegate {

    hidden var _job;

    function initialize() {
        SyncDelegate.initialize();
    }

    function onStartSync() as Void {
        _job = new SyncJob();
        _job.start();
    }

    function isSyncNeeded() as Boolean {
        return true;
    }

    function onStopSync() as Void {
        if (_job != null) {
            _job.cancel();
        }
        Communications.cancelAllRequests();
        Communications.notifySyncComplete("Sync cancelled");
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

    function initialize() {
        _api = new PocketCastsApi();
    }

    function start() {
        log("sync start");
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
        Communications.notifySyncProgress(5);
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
        Communications.notifySyncProgress(5 + (5 * _targets.size()) / _max);
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
            if (_old[i]["ref"] != null && EpisodeStore.findByUuid(_targets, _old[i]["uuid"]) == null) {
                Media.deleteCachedItem(new Media.ContentRef(_old[i]["ref"], Media.CONTENT_TYPE_AUDIO));
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
        log("download " + ep["title"]);
        Communications.makeWebRequest(ep["url"], null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_AUDIO,
            :mediaEncoding => encodingFor(ep),
            :fileDownloadProgressCallback => method(:onDownloadProgress)
        }, method(:onDownloaded));
    }

    function onDownloadProgress(bytes as Number, total as Number?) as Void {
        var frac = (total == null || total == 0) ? 0.0 : bytes.toFloat() / total;
        var overall = (_dlIdx + frac) / _toDownload.size();
        Communications.notifySyncProgress((10 + 90 * overall).toNumber());
    }

    function onDownloaded(code as Number, data as Null or ByteArray or Dictionary or String or PersistedContent.Iterator) as Void {
        if (_cancelled) { return; }
        log("download -> " + code);
        if (code == 200 && data != null) {
            _targets[_toDownload[_dlIdx]]["ref"] = (data as Media.ContentRef).getId();
            EpisodeStore.setEpisodes(_targets);
        } else {
            _failed++;
        }
        _dlIdx++;
        downloadNext();
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
        Communications.notifySyncProgress(100);
        var onWatch = 0;
        for (var i = 0; i < _targets.size(); i++) {
            if (_targets[i]["ref"] != null) { onWatch++; }
        }
        EpisodeStore.setLastResult({
            "downloaded" => _toDownload.size() - _failed,
            "failed" => _failed,
            "onWatch" => onWatch,
            "queued" => _targets.size()
        });
        if (_failed > 0) {
            var msg = "Downloaded " + (_toDownload.size() - _failed) + " of "
                + _toDownload.size() + " episodes, " + _failed + " failed";
            EpisodeStore.setLastError(msg);
            Communications.notifySyncComplete(msg);
        } else {
            EpisodeStore.setLastError(null);
            Communications.notifySyncComplete(null);
        }
    }

    hidden function fail(message) {
        log("sync failed: " + message);
        EpisodeStore.setLastError(message);
        Communications.notifySyncComplete(message);
    }

    hidden function log(msg) {
        System.println("[sync] " + msg);
    }
}
