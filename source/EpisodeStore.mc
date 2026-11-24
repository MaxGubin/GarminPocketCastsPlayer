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
// "pending": Dictionary uuid -> {"podcast", "position", "status"} of progress
//            updates not yet sent to Pocket Casts (sent on next sync).
module EpisodeStore {

    const KEY_TOKEN = "token";
    const KEY_EPISODES = "episodes";
    const KEY_PENDING = "pending";
    const KEY_ERROR = "lastError";
    const KEY_RESULT = "lastResult";

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
    //  "onWatch" => episodes on the watch, "queued" => episodes targeted}.
    function getLastResult() {
        return Application.Storage.getValue(KEY_RESULT);
    }

    function setLastResult(result) {
        Application.Storage.setValue(KEY_RESULT, result);
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

    function getPosition(uuid) {
        var ep = findByUuid(getEpisodes(), uuid);
        if (ep == null || ep["pos"] == null) {
            return 0;
        }
        return ep["pos"];
    }

    // Called from playback events. Updates local resume position and queues
    // the change for upload to Pocket Casts.
    function recordProgress(refId, position, finished) {
        if (refId == null) {
            return;
        }
        var eps = getEpisodes();
        for (var i = 0; i < eps.size(); i++) {
            var ep = eps[i];
            if (ep["ref"] != null && refId.equals(ep["ref"])) {
                if (position != null) {
                    ep["pos"] = position;
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
