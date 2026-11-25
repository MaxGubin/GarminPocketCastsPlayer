import Toybox.Lang;
import Toybox.Media;
import Toybox.WatchUi;

// "Menu" button in the native player. Pressing it calls
// PodcastContentDelegate.onCustomButton, which opens the app's menu
// (Sync now, choose an episode).
class MenuButton extends Media.CustomButton {
    function initialize() {
        CustomButton.initialize();
    }

    function getImage(image, highlighted) {
        return WatchUi.loadResource(image == Media.BUTTON_IMAGE_DETAIL ? Rez.Drawables.MenuDetail : Rez.Drawables.MenuIcon);
    }

    function getText(state) {
        return "Podcasts";
    }

    function getState() {
        return Media.BUTTON_STATE_DEFAULT;
    }
}
