import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Debug log. On the watch, System.println output goes to
// GARMIN/Apps/LOGS/<app file name>.TXT if that file exists.
module Log {

    // Prints "2026-11-26 19:43:20Z [tag] msg" (UTC).
    function line(tag as String, msg as String) as Void {
        var t = Gregorian.utcInfo(Time.now(), Time.FORMAT_SHORT);
        System.println(Lang.format("$1$-$2$-$3$ $4$:$5$:$6$Z [$7$] $8$", [
            t.year, (t.month as Number).format("%02d"), t.day.format("%02d"),
            t.hour.format("%02d"), t.min.format("%02d"), t.sec.format("%02d"),
            tag, msg
        ]));
    }
}
