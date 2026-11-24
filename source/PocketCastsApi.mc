import Toybox.Communications;
import Toybox.Lang;

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
