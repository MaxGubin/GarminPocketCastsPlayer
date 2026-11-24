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

    function getContentDelegate(arg) {
        return new PodcastContentDelegate();
    }

    function getSyncDelegate() {
        return new PodcastSyncDelegate();
    }

    function getSyncConfigurationView() {
        return [new SyncConfigView(), new SyncConfigDelegate()];
    }

    function getPlaybackConfigurationView() {
        return [new PlayerMenu(), new PlayerMenuDelegate()];
    }

    // Credentials changed in Garmin Connect -> force a fresh login on next sync.
    function onSettingsChanged() as Void {
        EpisodeStore.clearToken();
    }
}
