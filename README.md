# Podcast Sync (Garmin Connect IQ)

Audio Content Provider app that syncs your **Pocket Casts Up Next** queue to the
watch over Wi-Fi, plays it in the native music player with resume positions,
and sends playback progress back to Pocket Casts on the next sync.

Targets: fēnix 8 and fēnix 9 (all variants), epix (Gen 2 / Pro), Forerunner 965, Forerunner 970.

## How it works
1. **Sync** (watch: Music → source *Podcast Sync* → Sync, Wi-Fi configured on the watch):
   log in → upload queued progress → fetch Up Next → delete episodes no longer
   queued → download the first *N* unplayed episodes.
2. **Playback**: episodes play in queue order, starting at the saved position.
   Pause/skip/stop/complete events record the position locally.

### Sync API and charger syncs
Besides "Sync now", the watch syncs music providers by itself while charging.
The app uses the older, deprecated `Media` sync API (`Media.SyncDelegate`,
`Media.notifySyncProgress`, `Media.notifySyncComplete`, `Media.startSync`),
not the newer `Communications` one. With the `Communications` API (up to
0.14), on an epix (Gen 2), firmware 27.18, charger syncs showed no progress
and stayed "syncing" after the app reported completion, while "Sync now"
worked. The `Media` API is still in SDK 9.3 for all target devices, but
Garmin says it may be removed after System 9.

Other details in `source/PodcastSyncDelegate.mc`:
- `isSyncNeeded()` always returns true. When it returns false, the watch
  skips the sync, including one started with "Sync now".
- The running sync is kept in a global (`gSyncJob`), not in the delegate: the
  watch can call `onStopSync` on a different delegate instance than
  `onStartSync`.
- A download cancelled by the watch (`REQUEST_CANCELLED`) ends the sync; it
  doesn't fall back to the original file.

Pocket Casts API used (unofficial, see `source/PocketCastsApi.mc`):
`/user/login`, `/up_next/list`, `/sync/update_episode`.

## Setup
1. Install the Connect IQ SDK Manager (https://developer.garmin.com/connect-iq/sdk/),
   then the latest SDK and the device files for the watches above.
2. Developer key:
   ```
   openssl genrsa -out developer_key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
   ```
3. Build: `monkeyc -f monkey.jungle -d fr965 -y developer_key.der -o bin/PodcastSync.prg`
4. Sideload: copy `bin/PodcastSync.prg` to `GARMIN/APPS/` on the watch over USB.
5. Set email, password and episode count in the app's settings
   (Garmin Connect app → device → Connect IQ apps, or the simulator's settings editor).
   Accounts that sign in with Google/Apple need a Pocket Casts password set first.

## Debug log
The app logs each sync step with a UTC timestamp and the app version (see
`source/Log.mc`). On the watch, `System.println` output goes to
`GARMIN/Apps/LOGS/<file name>.TXT` only if that file exists, so create an
empty one over USB. The file name is that of the installed `.prg`:
`PodcastSync.TXT` when sideloaded, the store's name for the app (e.g.
`GBO41547.TXT`) when installed from the store. When the file gets large, the
watch moves it to `.BAK` and starts a new one. Crashes are recorded in
`GARMIN/Apps/LOGS/CIQ_LOG.YML` (or `.BAK`).

On Linux, the watch is an MTP device. Over SSH there is no desktop session
to grant access, so first run
`sudo chmod 666 /dev/bus/usb/<bus>/<device>` (from `lsusb`; the device
number changes each time the watch is plugged in), then use `gio mount` /
`gio copy` with the `mtp://` location shown by `gio mount -li`.

## Checking the API
`PC_EMAIL=... PC_PASSWORD=... scripts/pc_api_check.sh` — prints the Up Next fields
the app relies on (`uuid`, `podcast`, `url`, `playingStatus`, `playedUpTo`).
Add `PC_TEST_UPDATE=1` to also test progress upload (re-sends the current position).
