import Toybox.Lang;
import Toybox.Media;
import Toybox.System;

// Receives playback events from the native media player.
class PodcastContentDelegate extends Media.ContentDelegate {

    hidden var _iterator;

    function initialize() {
        ContentDelegate.initialize();
        _iterator = new PodcastContentIterator();
    }

    function getContentIterator() {
        return _iterator;
    }

    function resetContentIterator() {
        _iterator = new PodcastContentIterator();
        return _iterator;
    }

    // Save resume position whenever playback leaves an episode or pauses.
    function onSong(contentRefId, songEvent, playbackPosition) {
        System.println("[play] ref=" + contentRefId + " event=" + songEvent + " pos=" + playbackPosition);
        if (songEvent == Media.SONG_EVENT_COMPLETE) {
            EpisodeStore.recordProgress(contentRefId, playbackPosition, true);
        } else if (songEvent == Media.SONG_EVENT_PAUSE
                || songEvent == Media.SONG_EVENT_STOP
                || songEvent == Media.SONG_EVENT_SKIP_NEXT
                || songEvent == Media.SONG_EVENT_SKIP_PREVIOUS
                || songEvent == Media.SONG_EVENT_PLAYBACK_NOTIFY) {
            EpisodeStore.recordProgress(contentRefId, playbackPosition, false);
        }
    }

    function onThumbsUp(contentRefId) {}
    function onThumbsDown(contentRefId) {}
    function onShuffle() {}
    function onRepeat() {}
    function onAdAction(adContext) {}
}
