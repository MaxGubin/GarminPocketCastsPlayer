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

## Checking the API
`PC_EMAIL=... PC_PASSWORD=... scripts/pc_api_check.sh` — prints the Up Next fields
the app relies on (`uuid`, `podcast`, `url`, `playingStatus`, `playedUpTo`).
Add `PC_TEST_UPDATE=1` to also test progress upload (re-sends the current position).
