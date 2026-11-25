import Toybox.Application;
import Toybox.Lang;

// Persistent state kept in Application.Storage.
//
// "episodes": Array of Dictionary, in Up Next order:
//     "uuid"    episode uuid (Pocket Casts)
//     "podcast" podcast uuid
//     "title"   episode title
//     "url"     audio URL
//     "ref"     media cache ContentRef id once downloaded, else null
//     "pos"     resume position in seconds
//     "done"    true once played to the end on the watch
//     "speed"   speed of the downloaded file in percent (100 = original
//               timing, 150 = converted to 1.5x by the speed service)
//     "kbps"    bitrate requested from the speed service, null for originals
//
// "pos" is always in the episode's real timeline, as Pocket Casts uses it.
// The player works in the file's timeline; at 150 %, 20:00 in the file is
// 30:00 in the episode. toFileTime / toEpisodeTime convert between them.
// "pending": Dictionary uuid -> {"podcast", "position", "status"} of progress
//            updates not yet sent to Pocket Casts (sent on next sync).
module EpisodeStore {

    const KEY_TOKEN = "token";
    const KEY_EPISODES = "episodes";
    const KEY_PENDING = "pending";
    const KEY_ERROR = "lastError";
    const KEY_RESULT = "lastResult";
    const KEY_NOW = "nowRef";
    const KEY_PLAYING = "playing";

    // Pocket Casts playing status values
    const STATUS_IN_PROGRESS = 2;
    const STATUS_PLAYED = 3;

    function getToken() {
        return Application.Storage.getValue(KEY_TOKEN);
    }

    function setToken(token) {
        Application.Storage.setValue(KEY_TOKEN, token);
    }

    function clearToken() {
        Application.Storage.deleteValue(KEY_TOKEN);
    }

    // Message from the last sync if it failed, else null. Shown on the
    // sync and no-episodes screens.
    function getLastError() {
        return Application.Storage.getValue(KEY_ERROR);
    }

    function setLastError(message) {
        if (message == null) {
            Application.Storage.deleteValue(KEY_ERROR);
        } else {
            Application.Storage.setValue(KEY_ERROR, message);
        }
    }

    // Outcome of the last completed sync, shown on the sync screen:
    // {"downloaded" => new this sync, "failed" => failed downloads,
    //  "onWatch" => episodes on the watch, "queued" => episodes targeted,
    //  "serviceError" => speed server error code if it failed, else null}.
    function getLastResult() {
        return Application.Storage.getValue(KEY_RESULT);
    }

    function setLastResult(result) {
        Application.Storage.setValue(KEY_RESULT, result);
    }

    // Episode the player last started, and whether it is playing right now.
    // There is no API to ask the player, so this is tracked from onSong events.
    function setNowPlaying(refId, playing) {
        if (refId != null) {
            Application.Storage.setValue(KEY_NOW, refId);
        }
        Application.Storage.setValue(KEY_PLAYING, playing);
    }

    function getNowRef() {
        return Application.Storage.getValue(KEY_NOW);
    }

    function isPlaying() {
        return Application.Storage.getValue(KEY_PLAYING) == true;
    }

    function getEpisodes() {
        var eps = Application.Storage.getValue(KEY_EPISODES);
        return eps == null ? [] : eps;
    }

    function setEpisodes(eps) {
        Application.Storage.setValue(KEY_EPISODES, eps);
    }

    function findByUuid(eps, uuid) {
        for (var i = 0; i < eps.size(); i++) {
            if (uuid.equals(eps[i]["uuid"])) {
                return eps[i];
            }
        }
        return null;
    }

    // Downloaded episodes that haven't been finished, in queue order.
    function getPlayable() {
        var all = getEpisodes();
        var out = [];
        for (var i = 0; i < all.size(); i++) {
            if (all[i]["ref"] != null && all[i]["done"] != true) {
                out.add(all[i]);
            }
        }
        return out;
    }

    function speedOf(ep) {
        var s = ep["speed"];
        return (s == null || s <= 0) ? 100 : s;
    }

    // Episode seconds -> seconds in the downloaded file.
    function toFileTime(ep, seconds) {
        return (seconds * 100) / speedOf(ep);
    }

    // Seconds in the downloaded file -> episode seconds.
    function toEpisodeTime(ep, seconds) {
        return (seconds * speedOf(ep)) / 100;
    }

    // Resume position for the player, in the file's timeline.
    function getPosition(uuid) {
        var ep = findByUuid(getEpisodes(), uuid);
        if (ep == null || ep["pos"] == null) {
            return 0;
        }
        return toFileTime(ep, ep["pos"]);
    }

    // Called from playback events with the player's position (file timeline).
    // Updates the local resume position and queues it for upload to Pocket
    // Casts, both converted to the episode's timeline.
    function recordProgress(refId, position, finished) {
        if (refId == null) {
            return;
        }
        var eps = getEpisodes();
        for (var i = 0; i < eps.size(); i++) {
            var ep = eps[i];
            if (ep["ref"] != null && refId.equals(ep["ref"])) {
                if (position != null && position >= 0) {
                    ep["pos"] = toEpisodeTime(ep, position);
                }
                if (finished) {
                    ep["done"] = true;
                }
                setEpisodes(eps);
                queueProgress(ep["uuid"], ep["podcast"], ep["pos"],
                              finished ? STATUS_PLAYED : STATUS_IN_PROGRESS);
                return;
            }
        }
    }

    function getPending() {
        var p = Application.Storage.getValue(KEY_PENDING);
        return p == null ? {} : p;
    }

    function queueProgress(uuid, podcast, position, status) {
        var p = getPending();
        // Never downgrade a "played" update that hasn't been sent yet.
        var prev = p[uuid];
        if (prev != null && prev["status"] == STATUS_PLAYED) {
            status = STATUS_PLAYED;
        }
        p[uuid] = {"podcast" => podcast, "position" => position, "status" => status};
        Application.Storage.setValue(KEY_PENDING, p);
    }

    function removePending(uuid) {
        var p = getPending();
        p.remove(uuid);
        Application.Storage.setValue(KEY_PENDING, p);
    }
}
