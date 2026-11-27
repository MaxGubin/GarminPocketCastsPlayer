# Connect IQ beta upload: Podcast Sync

Package: `bin/PodcastSync.iq`, built with `monkeyc -e -r -f monkey.jungle -y developer_key.der -o bin/PodcastSync.iq`
Image:   `store/store_icon.png` (500x500)

## Upload form
- **Beta app:** yes (only visible to the uploading account)
- **Title:** Podcast Sync
- **Version:** 0.18 (must match `APP_VERSION` in `source/Version.mc`)
- **Category:** Music (audio content provider)
- **Description:**
  Syncs your podcast Up Next queue to the watch over Wi-Fi and plays it in the
  built-in music player, resuming where you left off. Playback progress is sent
  back to your account on the next sync.

  Setup: in Garmin Connect, open this app's settings and enter your account
  email and password and the number of episodes to keep on the watch (1–20).
  For play speed and bitrate, also enter the speed server URL and API key.
  Then on the watch: Music → Music Providers → Podcast Sync → Sync.

- **What's new (0.18):** "Sync now" in the Podcasts menu shows when the last
  sync finished: the time for a sync today, otherwise the date.
- **What's new (0.15):** Syncs that the watch starts while charging now show
  progress and finish properly; before, they showed no progress and could
  stay "syncing" after all episodes were downloaded. Cancelling a sync no
  longer keeps downloading in the background.
- **What's new (0.11):** Fixing sync when charging
- **What's new (0.10):** Faster sync with the speed server: it converts the next
  episode while the watch downloads the current one, and converts each episode
  only once.
- **What's new (0.8):** Speed server URL and API key are app settings. The menu
  shows "Speed server failed" (e.g. wrong API key) when episodes had to be
  downloaded at 1.0x instead. New "About" menu item with the version and the
  current speed and bitrate.
- **What's new (0.7):** Play speed (1.0x–2.0x) and MP3 bitrate (64/128 kbps)
  settings. Episodes are converted by a speed server; positions are converted
  so the watch and Pocket Casts stay in step. Falls back to the original file
  if the server can't be reached.
- **What's new (0.6):** A "Podcasts" button in the player opens a menu with
  "Sync now" and "Episodes", to pick which downloaded episode to play. Replaces
  the Library button, which had no icon.
- **What's new (0.5):** While an episode is playing, opening the app goes straight
  to the player instead of the menu, and playback continues with the last
  episode played rather than the first in the queue.
- **What's new (0.4):** The Podcasts menu refreshes after a sync, so the episode
  count and "Last: N new" are current.
- **What's new (0.3):** The Podcasts menu now has "Sync now" even when episodes are
  downloaded, and shows how many were downloaded by the last sync. The player's
  Library button opens this menu.
- **What's new (0.1.1):** When nothing is downloaded, a menu offers "Sync now" and
  "Open player" (to reach Music Providers) instead of a dead end. Failed syncs show
  the reason, e.g. a wrong password, on the sync screen and in that menu.
