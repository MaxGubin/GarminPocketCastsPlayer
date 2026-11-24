#!/usr/bin/env bash
# Exercise the Pocket Casts endpoints the watch app uses.
# Usage: PC_EMAIL=... PC_PASSWORD=... scripts/pc_api_check.sh
set -euo pipefail
: "${PC_EMAIL:?set PC_EMAIL}" "${PC_PASSWORD:?set PC_PASSWORD}"
API=https://api.pocketcasts.com

echo "== login"
LOGIN=$(jq -n --arg e "$PC_EMAIL" --arg p "$PC_PASSWORD" '{email:$e,password:$p,scope:"webplayer"}' |
  curl -sS -X POST "$API/user/login" -H 'Content-Type: application/json' --data-binary @-)
TOKEN=$(jq -r '.token // empty' <<<"$LOGIN")
[ -n "$TOKEN" ] || { echo "login failed: $(jq -c 'del(.token)' <<<"$LOGIN" 2>/dev/null || echo "$LOGIN")"; exit 1; }
echo "ok (response keys: $(jq -c 'keys' <<<"$LOGIN"))"

echo "== up_next/list"
UPNEXT=$(curl -sS -X POST "$API/up_next/list" -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
  --data '{"version":2,"model":"webplayer","serverModified":0,"showPlayStatus":true}')
echo "response bytes: ${#UPNEXT}"
echo "top-level keys: $(jq -c 'keys' <<<"$UPNEXT")"
echo "episode fields: $(jq -c '.episodes[0] | keys' <<<"$UPNEXT")"
jq -r '.episodes[:5][] | "\(.uuid)  \(.title)"' <<<"$UPNEXT"

echo "== user/episode (play state for first Up Next episode)"
FIRST=$(jq -c '.episodes[0] | {uuid, podcast}' <<<"$UPNEXT")
DETAIL=$(curl -sS -X POST "$API/user/episode" -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" --data "$FIRST")
echo "response bytes: ${#DETAIL}"
jq -c '{title, playingStatus, playedUpTo, duration, fileType}' <<<"$DETAIL"

if [ "${PC_TEST_UPDATE:-0}" = 1 ]; then
  echo "== sync/update_episode (re-sends the current position and status, no change)"
  BODY=$(jq -c --argjson f "$FIRST" '{uuid:$f.uuid, podcast:$f.podcast, position:(.playedUpTo // 0), status:(.playingStatus // 1)}' <<<"$DETAIL")
  curl -sS -o /dev/null -w 'HTTP %{http_code}\n' -X POST "$API/sync/update_episode" -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" --data "$BODY"
fi
