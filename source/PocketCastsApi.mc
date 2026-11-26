import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Media;

// Thin wrapper over the (unofficial) Pocket Casts web API, as used by the
// Pocket Casts web player and open-source mobile apps.
// All callbacks have the signature  function(code as Number, data) as Void.
class PocketCastsApi {

    const BASE_URL = "https://api.pocketcasts.com";

    function initialize() {
    }

    // -> {"token": "...", "uuid": "...", "email": "..."}
    function login(email, password, callback) {
        post("/user/login",
             {"email" => email, "password" => password, "scope" => "webplayer"},
             false, callback);
    }

    // -> {"episodes": [{"uuid", "title", "url", "podcast", "published"}], ...}
    // Note: no play state here; see episode().
    function upNext(callback) {
        post("/up_next/list",
             {"version" => 2, "model" => "webplayer", "serverModified" => 0, "showPlayStatus" => true},
             true, callback);
    }

    // -> {"uuid", "duration", "fileType", "playingStatus", "playedUpTo", "podcastTitle", ...}
    function episode(uuid, podcast, callback) {
        post("/user/episode", {"uuid" => uuid, "podcast" => podcast}, true, callback);
    }

    // status: 2 = in progress, 3 = played. position in seconds.
    function updateEpisode(uuid, podcast, position, status, callback) {
        post("/sync/update_episode",
             {"uuid" => uuid, "podcast" => podcast, "position" => position, "status" => status},
             true, callback);
    }

    // Speed server (server/), from the app settings. Without both a URL and
    // an API key, episodes are downloaded as original files.
    function hasAudioService() {
        return serviceUrl() != null && serviceKey() != null;
    }

    // Settings value, or null if empty.
    hidden function setting(key) {
        var v = Application.Properties.getValue(key);
        if (v == null) {
            return null;
        }
        v = v.toString();
        return v.length() > 0 ? v : null;
    }

    // Base URL from the settings, accepting it with or without a trailing
    // "/" or "/audio".
    hidden function serviceUrl() {
        var url = setting("serviceUrl");
        if (url == null) {
            return null;
        }
        while (url.length() > 0 && url.substring(url.length() - 1, url.length()).equals("/")) {
            url = url.substring(0, url.length() - 1);
        }
        if (url.length() >= 6 && url.substring(url.length() - 6, url.length()).equals("/audio")) {
            url = url.substring(0, url.length() - 6);
        }
        return url.length() > 0 ? url : null;
    }

    hidden function serviceKey() {
        return setting("serviceKey");
    }

    hidden function serviceParams(url, speedPercent, kbps) {
        return {
            "url" => url,
            "speed" => (speedPercent / 100.0).format("%.2f"),
            "kbps" => kbps
        };
    }

    // Episode audio converted by the speed service: sped up by speedPercent
    // (100 = 1.0x), re-encoded as MP3 at kbps. Always MP3. nextUrl (or null)
    // is the episode that will be downloaded after this one; the service
    // converts it in the background meanwhile.
    function downloadConverted(url, nextUrl, speedPercent, kbps, progress, callback) {
        var params = serviceParams(url, speedPercent, kbps);
        if (nextUrl != null) {
            params["next"] = nextUrl;
        }
        Communications.makeWebRequest(serviceUrl() + "/audio", params, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => {"X-Api-Key" => serviceKey()},
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_AUDIO,
            :mediaEncoding => Media.ENCODING_MP3,
            :fileDownloadProgressCallback => progress
        }, callback);
    }

    // Episode audio straight from the podcast host.
    function downloadOriginal(url, encoding, progress, callback) {
        Communications.makeWebRequest(url, null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_AUDIO,
            :mediaEncoding => encoding,
            :fileDownloadProgressCallback => progress
        }, callback);
    }

    hidden function post(path, body, authenticated, callback) {
        var headers = {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON};
        if (authenticated) {
            headers["Authorization"] = "Bearer " + EpisodeStore.getToken();
        }
        Communications.makeWebRequest(BASE_URL + path, body, {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, callback);
    }
}
