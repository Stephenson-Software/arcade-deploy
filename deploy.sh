#!/usr/bin/env bash
# Upload one game bundle to arcade. Used by action.yml; also runnable by hand
# with the same ARCADE_* variables set.
set -euo pipefail

fail() { echo "::error::arcade-deploy: $*" >&2; exit 1; }

[ -n "${ARCADE_SLUG:-}" ] || fail "slug is empty - set the slug input to the game's slug in games.yaml"
[ -n "${ARCADE_TOKEN:-}" ] || fail "token is empty - is the ARCADE_TOKEN secret set on this repository?"
ARCADE_INDEX=${ARCADE_INDEX:-web/index.html}
ARCADE_GAME_ZIP=${ARCADE_GAME_ZIP:-web/game.zip}
ARCADE_VERSION_FILE=${ARCADE_VERSION_FILE:-version.txt}
ARCADE_URL=${ARCADE_URL:-https://play.danielstephenson.dev}
ARCADE_ACTIVATE=${ARCADE_ACTIVATE:-true}
ARCADE_SKIP_EXISTING=${ARCADE_SKIP_EXISTING:-false}

[[ "$ARCADE_SLUG" =~ ^[a-z][a-z0-9-]{1,30}$ ]] || fail "slug '$ARCADE_SLUG' is not a valid slug"
ARCADE_SITE_DIR=${ARCADE_SITE_DIR:-}
if [ -n "$ARCADE_SITE_DIR" ]; then
  [ -f "$ARCADE_SITE_DIR/index.html" ] || fail "$ARCADE_SITE_DIR/index.html does not exist (did the build step run?)"
  [ -f "$ARCADE_VERSION_FILE" ] || fail "$ARCADE_VERSION_FILE does not exist"
else
  for f in "$ARCADE_INDEX" "$ARCADE_GAME_ZIP" "$ARCADE_VERSION_FILE"; do
    [ -f "$f" ] || fail "$f does not exist (did the build step run?)"
  done
fi
version=$(tr -d '[:space:]' < "$ARCADE_VERSION_FILE")
[[ "$version" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$ ]] || fail "version '$version' from $ARCADE_VERSION_FILE is not a valid version"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [ -n "$ARCADE_SITE_DIR" ]; then
  # A static site: the whole directory, with version.txt written at its root.
  mkdir "$work/site"
  cp -R "$ARCADE_SITE_DIR"/. "$work/site/"
  printf '%s\n' "$version" > "$work/site/version.txt"
  # Links are refused by arcade; dereference them here rather than fail there.
  tar -C "$work/site" --dereference -cf "$work/bundle.tar" .
else
  cp "$ARCADE_INDEX" "$work/index.html"
  cp "$ARCADE_GAME_ZIP" "$work/game.zip"
  printf '%s\n' "$version" > "$work/version.txt"
  tar -C "$work" -cf "$work/bundle.tar" index.html game.zip version.txt
fi

# The token goes in a header file, not on the command line.
umask 077
printf 'Authorization: Bearer %s\n' "$ARCADE_TOKEN" > "$work/auth"

query=""
[ "$ARCADE_ACTIVATE" = "false" ] && query="?activate=false"
endpoint="${ARCADE_URL%/}/api/games/$ARCADE_SLUG/versions/$version$query"
echo "Uploading $ARCADE_SLUG $version ($(wc -c < "$work/bundle.tar") bytes) to ${ARCADE_URL%/}"
skipped=false
status=$(curl -sS --connect-timeout 20 -o "$work/response" -w '%{http_code}' \
  -X PUT -H @"$work/auth" -H 'Content-Type: application/x-tar' \
  --data-binary @"$work/bundle.tar" "$endpoint") || fail "could not reach $ARCADE_URL"
body=$(tr -s '\n ' ' ' < "$work/response")

case "$status" in
  201) echo "$body" ;;
  409)
    if [ "$ARCADE_SKIP_EXISTING" = "true" ]; then
      echo "::notice::$ARCADE_SLUG $version is already deployed; skipping (skip-existing)."
      skipped=true
    else
      fail "$ARCADE_SLUG $version is already deployed and versions are immutable - bump version.txt, or set skip-existing: true for re-runs. Server said: $body"
    fi ;;
  401|403) fail "the server refused the token for '$ARCADE_SLUG' ($status). Check the ARCADE_TOKEN secret and the token_sha256 in games.yaml. Server said: $body" ;;
  *) fail "upload failed with HTTP $status: $body" ;;
esac

base=${ARCADE_URL#https://}; base=${base#http://}; base=${base%/}
{
  echo "version=$version"
  echo "url=https://$ARCADE_SLUG.$base/"
} >> "${GITHUB_OUTPUT:-/dev/null}"
if [ "$skipped" = true ]; then :; elif [ "$ARCADE_ACTIVATE" = "false" ]; then echo "Stored (not live) for https://$ARCADE_SLUG.$base/"; else echo "Live at https://$ARCADE_SLUG.$base/"; fi
