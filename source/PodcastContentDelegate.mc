import Toybox.Lang;
import Toybox.Media;
import Toybox.System;
import Toybox.WatchUi;

// Receives playback events from the native media player.
class PodcastContentDelegate extends Media.ContentDelegate {

    hidden var _iterator;

    function initialize(startRef) {
        ContentDelegate.initialize();
        _iterator = new PodcastContentIterator(startRef);
    }

    function getContentIterator() {
        return _iterator;
    }

    function resetContentIterator() {
        _iterator = new PodcastContentIterator(null);
        return _iterator;
    }

    // Save resume position whenever playback leaves an episode or pauses.
    function onSong(contentRefId, songEvent, playbackPosition) {
        System.println("[play] ref=" + contentRefId + " event=" + songEvent + " pos=" + playbackPosition);
        if (songEvent == Media.SONG_EVENT_START || songEvent == Media.SONG_EVENT_RESUME) {
            EpisodeStore.setNowPlaying(contentRefId, true);
        } else if (songEvent == Media.SONG_EVENT_PAUSE
                || songEvent == Media.SONG_EVENT_STOP
                || songEvent == Media.SONG_EVENT_COMPLETE) {
            EpisodeStore.setNowPlaying(null, false);
        }

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

    // The player's "Podcasts" button (MenuButton): open the app's menu.
    function onCustomButton(button) {
        WatchUi.pushView(new PlayerMenu(), new PlayerMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function onThumbsUp(contentRefId) {}
    function onThumbsDown(contentRefId) {}
    function onShuffle() {}
    function onRepeat() {}
    function onAdAction(adContext) {}
}
