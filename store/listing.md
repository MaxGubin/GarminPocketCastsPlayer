# Connect IQ beta upload: Podcast Sync

Package: `bin/PodcastSync.iq`, built with `monkeyc -e -r -f monkey.jungle -y developer_key.der -o bin/PodcastSync.iq`
Image:   `store/store_icon.png` (500x500)

## Upload form
- **Beta app:** yes (only visible to the uploading account)
- **Title:** Podcast Sync
- **Version:** 0.4
- **Category:** Music (audio content provider)
- **Description:**
  Syncs your podcast Up Next queue to the watch over Wi-Fi and plays it in the
  built-in music player, resuming where you left off. Playback progress is sent
  back to your account on the next sync.

  Setup: in Garmin Connect, open this app's settings and enter your account
  email and password and the number of episodes to keep on the watch (1–20).
  Then on the watch: Music → Music Providers → Podcast Sync → Sync.

- **What's new (0.4):** The Podcasts menu refreshes after a sync, so the episode
  count and "Last: N new" are current.
- **What's new (0.3):** The Podcasts menu now has "Sync now" even when episodes are
  downloaded, and shows how many were downloaded by the last sync. The player's
  Library button opens this menu.
- **What's new (0.1.1):** When nothing is downloaded, a menu offers "Sync now" and
  "Open player" (to reach Music Providers) instead of a dead end. Failed syncs show
  the reason, e.g. a wrong password, on the sync screen and in that menu.
