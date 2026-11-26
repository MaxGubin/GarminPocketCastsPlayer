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
        startManualSync();
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
            add(new WatchUi.MenuItem("Episodes", "Choose one to play", :episodes, null));
        }
        var error = EpisodeStore.getLastError();
        if (error != null) {
            add(new WatchUi.MenuItem("Last sync failed", error, :error, null));
        }
        var result = EpisodeStore.getLastResult();
        var syncSub = (result != null && error == null)
            ? "Last: " + result["downloaded"] + " new" : "Needs Wi-Fi";
        if (result != null && result["serviceError"] != null) {
            // Downloads fell back to original files (1.0x).
            add(new WatchUi.MenuItem("Speed server failed", serviceErrorText(result["serviceError"]), :speedError, null));
        }
        add(new WatchUi.MenuItem("Sync now", syncSub, :sync, null));
        if (n == 0) {
            add(new WatchUi.MenuItem("Open player", "Switch music provider", :player, null));
        }
        add(new WatchUi.MenuItem("About", "Version " + APP_VERSION, :about, null));
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
            startManualSync();
        } else if (id == :about) {
            WatchUi.pushView(new AboutView(), new WatchUi.BehaviorDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :speedError) {
            // Informational only.
        } else if (id == :episodes) {
            WatchUi.pushView(new EpisodesMenu(), new EpisodesMenuDelegate(), WatchUi.SLIDE_LEFT);
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

// Downloaded, unfinished episodes in queue order; selecting one plays it from
// its saved position.
class EpisodesMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Episodes"});
        var eps = EpisodeStore.getPlayable();
        var now = EpisodeStore.getNowRef();
        for (var i = 0; i < eps.size(); i++) {
            var ep = eps[i];
            var pos = ep["pos"] == null ? 0 : ep["pos"];
            var sub = pos > 0 ? "At " + formatTime(pos) : "Not started";
            if (now != null && now.equals(ep["ref"])) {
                sub = "Current, " + sub.substring(0, 1).toLower() + sub.substring(1, sub.length());
            }
            addItem(new WatchUi.MenuItem(shortTitle(ep["title"]), sub, ep["ref"], null));
        }
    }
}

class EpisodesMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        // Passed to getContentDelegate(), which starts the playlist here.
        Media.startPlayback(item.getId());
    }
}

// Sub-label for "Speed server failed"; episodes were downloaded at 1.0x.
function serviceErrorText(code) {
    if (code == 401) { return "Wrong API key"; }
    if (code == -1001) { return "URL must be https"; }
    if (code < 0) { return "Unreachable (" + code + ")"; }
    return "HTTP " + code;
}

// Menu labels are cut to one line, and episodes of a series often share a
// long prefix ("Series: Episode name"). Show the part after the last ": ".
function shortTitle(title) {
    if (title == null) {
        return "Episode";
    }
    var rest = title;
    var i = rest.find(": ");
    while (i != null) {
        rest = rest.substring(i + 2, rest.length());
        i = rest.find(": ");
    }
    return rest.length() >= 4 ? rest : title;
}

// h:mm:ss or m:ss
function formatTime(seconds) {
    var h = seconds / 3600;
    var m = (seconds % 3600) / 60;
    var s = seconds % 60;
    if (h > 0) {
        return h + ":" + m.format("%02d") + ":" + s.format("%02d");
    }
    return m + ":" + s.format("%02d");
}

// Shown for a moment while handing over to the player when an episode is
// already playing. Returning a view is required; this one leaves immediately.
class OpenPlayerView extends WatchUi.View {
    function initialize() {
        View.initialize();
    }

    function onShow() {
        Media.startPlayback(null);
    }

    function onUpdate(dc) {
        drawCentered(dc, "Opening player...");
    }
}

// Version and the current speed settings.
class AboutView extends WatchUi.View {
    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        var speed = Application.Properties.getValue("playSpeed");
        var kbps = Application.Properties.getValue("bitrate");
        var server = new PocketCastsApi().hasAudioService();
        var text = "Podcast Sync\nVersion " + APP_VERSION + "\n\n";
        if (server) {
            text += "Speed " + ((speed == null ? 100 : speed) / 100.0).format("%.2f") + "x, "
                + (kbps == null ? 64 : kbps) + " kbps";
        } else {
            text += "Speed server not set:\nepisodes play at 1.0x";
        }
        drawWrapped(dc, text, Graphics.COLOR_WHITE);
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
