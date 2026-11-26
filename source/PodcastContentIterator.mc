import Toybox.Lang;
import Toybox.Media;
import Toybox.System;

// Plays downloaded, unfinished episodes in Up Next order, resuming each at
// its saved position.
class PodcastContentIterator extends Media.ContentIterator {

    hidden var _episodes;
    hidden var _index = 0;

    // startRef: episode to start with, or null for the one played last.
    function initialize(startRef) {
        ContentIterator.initialize();
        _episodes = EpisodeStore.getPlayable();
        // Continue with the chosen episode, or the one that was playing last,
        // rather than always the first.
        var now = startRef != null ? startRef : EpisodeStore.getNowRef();
        Log.line("iter", "startRef=" + startRef + " nowRef=" + EpisodeStore.getNowRef() + " playable=" + _episodes.size());
        if (now != null) {
            for (var i = 0; i < _episodes.size(); i++) {
                if (now.equals(_episodes[i]["ref"])) {
                    _index = i;
                    break;
                }
            }
        }
    }

    function canSkip() {
        return true;
    }

    function shuffling() {
        return false;
    }

    function getPlaybackProfile() {
        var profile = new Media.PlaybackProfile();
        profile.playbackControls = [
            Media.PLAYBACK_CONTROL_SKIP_BACKWARD,
            Media.PLAYBACK_CONTROL_PLAYBACK,
            Media.PLAYBACK_CONTROL_SKIP_FORWARD,
            Media.PLAYBACK_CONTROL_PREVIOUS,
            Media.PLAYBACK_CONTROL_NEXT,
            // Opens the app's menu: Sync now, choose an episode.
            new MenuButton()
        ];
        profile.attemptSkipAfterThumbsDown = false;
        profile.requirePlaybackNotification = false;
        profile.playbackNotificationThreshold = 30;
        profile.skipPreviousThreshold = 5;
        // Offer all preset speeds; the device defines the actual multipliers.
        profile.playSpeedMultipliers = [
            Media.PLAYBACK_SPEED_SLOW,
            Media.PLAYBACK_SPEED_NORMAL,
            Media.PLAYBACK_SPEED_FAST,
            Media.PLAYBACK_SPEED_FASTEST
        ];
        // Skip forward/back use the system default of 30 s. Other values would
        // need custom button icons (the built-in ones are labelled "30").
        return profile;
    }

    function get() {
        return contentAt(_index);
    }

    function next() {
        if (_index + 1 >= _episodes.size()) {
            return null;
        }
        _index++;
        return get();
    }

    function previous() {
        if (_index <= 0) {
            return null;
        }
        _index--;
        return get();
    }

    function peekNext() {
        return contentAt(_index + 1);
    }

    function peekPrevious() {
        return contentAt(_index - 1);
    }

    hidden function contentAt(i) {
        if (i < 0 || i >= _episodes.size()) {
            return null;
        }
        var ep = _episodes[i];
        var ref = new Media.ContentRef(ep["ref"], Media.CONTENT_TYPE_AUDIO);
        var cached = Media.getCachedContentObj(ref);
        if (cached == null) {
            return null;
        }
        // Read position fresh: it may have changed since the iterator was built.
        return new Media.ActiveContent(ref, cached.getMetadata(), EpisodeStore.getPosition(ep["uuid"]));
    }
}
