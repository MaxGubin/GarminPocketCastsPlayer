import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Media;
import Toybox.WatchUi;

// Draws `text` word-wrapped to fit inside the round screen.
function drawWrapped(dc, text, color) {
    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
    dc.clear();
    var w = dc.getWidth() * 3 / 4;
    var h = dc.getHeight() * 3 / 4;
    var fitted = Graphics.fitTextToArea(text, Graphics.FONT_XTINY, w, h, true);
    dc.setColor(color, Graphics.COLOR_TRANSPARENT);
    dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_XTINY, fitted,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
}

function drawCentered(dc, text) {
    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
    dc.clear();
    dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_SMALL, text,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
}

// ---- Sync configuration: shown when the user picks "Sync" -----------------

class SyncConfigView extends WatchUi.View {
    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        var email = Application.Properties.getValue("email");
        if (email == null || email.length() == 0) {
            drawCentered(dc, "Set Pocket Casts\nlogin in Garmin\nConnect settings");
            return;
        }
        var error = EpisodeStore.getLastError();
        if (error != null) {
            drawWrapped(dc, "Last sync failed\n\n" + error + "\n\nPress START to retry", Graphics.COLOR_ORANGE);
            return;
        }
        var count = Application.Properties.getValue("episodeCount");
        var result = EpisodeStore.getLastResult();
        if (result == null) {
            drawCentered(dc, "Sync " + count + " episodes\nfrom Up Next\n\nPress START");
            return;
        }
        drawCentered(dc, EpisodeStore.getPlayable().size() + " episode(s)\non watch\n"
            + "Last sync: " + result["downloaded"] + " new\n\nPress START to sync");
    }
}

class SyncConfigDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() {
        Communications.startSync();
        return true;
    }
}

// ---- Playback configuration: shown before playback starts -----------------
//
// A menu with Play / Sync now (and the last sync error, if any). It is also
// reachable from inside the native player through its Library button. Without
// episodes, "Open player" and BACK lead to the native player (and its Music
// Providers menu), so the user is never stuck in this app.

// Rebuilt every time it is shown, so the counts are current after returning
// from a sync.
class PlayerMenu extends WatchUi.Menu2 {
    hidden var _count = 0;

    function initialize() {
        Menu2.initialize({:title => "Podcasts"});
        fill();
    }

    function onShow() {
        while (_count > 0) {
            deleteItem(0);
            _count--;
        }
        fill();
        Menu2.onShow();
    }

    hidden function add(item) {
        addItem(item);
        _count++;
    }

    hidden function fill() {
        var n = EpisodeStore.getPlayable().size();
        setTitle(n > 0 ? "Podcasts" : "No episodes");
        if (n > 0) {
            add(new WatchUi.MenuItem("Play", n + " episode(s)", :play, null));
        }
        var error = EpisodeStore.getLastError();
        if (error != null) {
            add(new WatchUi.MenuItem("Last sync failed", error, :error, null));
        }
        var result = EpisodeStore.getLastResult();
        var syncSub = (result != null && error == null)
            ? "Last: " + result["downloaded"] + " new" : "Needs Wi-Fi";
        add(new WatchUi.MenuItem("Sync now", syncSub, :sync, null));
        if (n == 0) {
            add(new WatchUi.MenuItem("Open player", "Switch music provider", :player, null));
        }
        setFocus(0);
    }
}

class PlayerMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :error) {
            WatchUi.pushView(new ErrorView(), new WatchUi.BehaviorDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :sync) {
            Communications.startSync();
        } else {
            Media.startPlayback(null);
        }
    }

    function onBack() {
        if (EpisodeStore.getPlayable().size() > 0) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else {
            Media.startPlayback(null);
        }
    }
}

// Full text of the last sync error (menu sub-labels are truncated).
class ErrorView extends WatchUi.View {
    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        var error = EpisodeStore.getLastError();
        drawWrapped(dc, "Last sync failed\n\n" + (error != null ? error : "-"), Graphics.COLOR_ORANGE);
    }
}
