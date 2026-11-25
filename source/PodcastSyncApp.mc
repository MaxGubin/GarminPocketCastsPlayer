import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Media;
import Toybox.WatchUi;

// Entry point. The watch's media player drives this app:
//  - "Sync" in the music source menu -> getSyncConfigurationView / getSyncDelegate
//  - playing music from this source  -> getPlaybackConfigurationView / getContentDelegate
class PodcastSyncApp extends Application.AudioContentProviderApp {

    function initialize() {
        AudioContentProviderApp.initialize();
    }

    // arg: ContentRef id of the episode to start with (from the Episodes
    // menu), or null to continue with the last played episode.
    function getContentDelegate(arg) {
        return new PodcastContentDelegate(arg);
    }

    function getSyncDelegate() {
        return new PodcastSyncDelegate();
    }

    function getSyncConfigurationView() {
        return [new SyncConfigView(), new SyncConfigDelegate()];
    }

    function getPlaybackConfigurationView() {
        // Already playing: go straight back to the player instead of the menu.
        if (EpisodeStore.isPlaying() && EpisodeStore.getPlayable().size() > 0) {
            return [new OpenPlayerView(), new WatchUi.BehaviorDelegate()];
        }
        return [new PlayerMenu(), new PlayerMenuDelegate()];
    }

    // Credentials changed in Garmin Connect -> force a fresh login on next sync.
    function onSettingsChanged() as Void {
        EpisodeStore.clearToken();
    }
}
