#!/bin/bash
# uninstall.sh — remove everything this repo installed outside the checkout.
#
#   bash uninstall.sh              stop and remove the app + LaunchAgents
#   bash uninstall.sh --purge      also delete cached events, sync state, logs, and the OAuth token
#   bash uninstall.sh --dry-run    print what would be removed, change nothing
#   bash uninstall.sh --legacy-only  remove ONLY the pre-rename install, keep the current one
#   bash uninstall.sh --purge --dry-run   rehearse a purge; --dry-run wins in any order
#   bash uninstall.sh --help       print usage and exit without touching anything
#
# Notes it synced from Drive are NOT touched, at any level. They are your files.
#
# It also removes a pre-rename install, when it finds one. This project was called
# meeting-notification-bar and its app was NextMeeting.app; upgrading across that rename otherwise
# leaves the old app, LaunchAgents and support directories behind, still running and still fetching.
# The legacy app is only removed after its CFBundleIdentifier is confirmed to be ours:
# ~/Applications/NextMeeting.app is also where the separate meeting-vault variant installs, and
# removing that one by name would take out an unrelated menu bar.
#
# --legacy-only exists because the common case is "I just installed the new one, now clear the old
# one", and a plain uninstall would remove the install you are standing on. It touches nothing
# belonging to meeting-bar, and with --purge it purges only the pre-rename directories, never the
# OAuth token.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ID="io.llinkas.meeting-bar"
DATA="$HOME/Library/Application Support/meeting-bar"
LOGS="$HOME/Library/Logs/meeting-bar"

# Pre-rename names. Kept so one uninstall also clears an install made before the project became
# meeting-bar, rather than silently leaving a second countdown running.
LEGACY_BUNDLE_ID="io.llinkas.meeting-notification-bar"
LEGACY_APP="$HOME/Applications/NextMeeting.app"
LEGACY_DATA="$HOME/Library/Application Support/meeting-notification-bar"
LEGACY_LOGS="$HOME/Library/Logs/meeting-notification-bar"

# Prints the header comment above, rather than a second copy of it. The copy this replaced had
# already drifted inside a single sitting — the header listed --help and the copy did not. Reading
# the file's own header by shape (everything after the shebang up to the first non-comment line)
# means the usage text cannot disagree with the documentation directly above it, and cannot
# truncate when someone adds a line.
usage() {
  awk 'NR > 1 && /^#/ { sub(/^#[ ]?/, ""); print; next } NR > 1 { exit }' "$0"
}

# Parse arguments BEFORE doing anything destructive, and reject what we do not recognise.
#
# This block used to be `[ "${1:-}" = "--purge" ] && PURGE=1`, with no validation and no help text.
# Every other argument — including `--help` — fell through to the removal code below and performed a
# real uninstall. That is exactly backwards: the cautious instinct (ask it what it does before
# running it) was the one that destroyed things, and it cost a live install during testing.
#
# Every argument is inspected, not just $1. The earlier version read `$1` alone and rejected a
# second argument outright, which was safe but unhelpful: `--purge --dry-run` is the natural way to
# ask "show me what purging would do" — you name the action, then qualify it — and being told "too
# many arguments" invites dropping the qualifier rather than reordering it. Now the combination
# works, and --dry-run wins wherever it appears, so the safety flag can never be the one silently
# discarded.
PURGE=0
DRY=0
LEGACY_ONLY=0
for a in "$@"; do
  case "$a" in
    --purge)       PURGE=1 ;;
    --dry-run)     DRY=1 ;;
    --legacy-only) LEGACY_ONLY=1 ;;
    -h|--help)     usage; exit 0 ;;
    *)             echo "unknown flag: $a" >&2; echo >&2; usage >&2; exit 2 ;;
  esac
done

run() { if [ "$DRY" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }

# Say "would remove" during a dry run. Announcing "removed" about something still on disk is the
# same class of lie as a footer that says "Updated" about a fetch that failed.
did() { if [ "$DRY" = 1 ]; then echo "==> would remove $*"; else echo "==> removed $*"; fi; }

LABELS=("$LEGACY_BUNDLE_ID.menubar" "$LEGACY_BUNDLE_ID.drive-sync")
[ "$LEGACY_ONLY" = 1 ] || LABELS=("$BUNDLE_ID.menubar" "$BUNDLE_ID.drive-sync" "${LABELS[@]}")

for label in "${LABELS[@]}"; do
  PLIST="$HOME/Library/LaunchAgents/$label.plist"
  # Only claim to have removed things that were actually there — the old version announced
  # "removed LaunchAgent" for agents that had never been installed.
  if launchctl print "gui/$UID/$label" >/dev/null 2>&1 || [ -f "$PLIST" ]; then
    run launchctl bootout "gui/$UID/$label" 2>/dev/null || true
    run rm -f "$PLIST"
    did "LaunchAgent $label"
  fi
done

if [ "$LEGACY_ONLY" = 0 ]; then
  if pgrep -f "MeetingBar.app/Contents/MacOS/MeetingBar" >/dev/null 2>&1; then
    run pkill -f "MeetingBar.app/Contents/MacOS/MeetingBar" || true
  fi
  if [ -d "$HOME/Applications/MeetingBar.app" ]; then
    run rm -rf "$HOME/Applications/MeetingBar.app"
    did "~/Applications/MeetingBar.app"
  fi
fi

# The pre-rename app, and only when it is ours. `pkill -f NextMeeting` and `rm -rf NextMeeting.app`
# are both addressed by name, and the meeting-vault variant installs under exactly that name — so
# the bundle identifier is read first, and nothing is touched when it does not match or cannot be
# read. Killing by name is how this script has taken out a live menu bar before.
if [ -d "$LEGACY_APP" ]; then
  LEGACY_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LEGACY_APP/Contents/Info.plist" 2>/dev/null || echo '')"
  if [ "$LEGACY_ID" = "$LEGACY_BUNDLE_ID" ]; then
    if pgrep -f "NextMeeting.app/Contents/MacOS/NextMeeting" >/dev/null 2>&1; then
      run pkill -f "NextMeeting.app/Contents/MacOS/NextMeeting" || true
    fi
    run rm -rf "$LEGACY_APP"
    did "~/Applications/NextMeeting.app (pre-rename install)"
  else
    echo "==> left $LEGACY_APP alone: bundle id is ${LEGACY_ID:-unreadable}, not $LEGACY_BUNDLE_ID"
  fi
elif [ "$LEGACY_ONLY" = 1 ]; then
  echo "==> no pre-rename install found at $LEGACY_APP"
fi

if [ "$PURGE" = 1 ] && [ "$LEGACY_ONLY" = 1 ]; then
  # Deliberately narrow: the pre-rename directories and nothing else. The token belongs to the
  # install that is staying.
  run rm -rf "$LEGACY_DATA" "$LEGACY_LOGS"
  if [ "$DRY" = 1 ]; then
    echo "==> would purge the pre-rename data and log directories"
  else
    echo "==> purged the pre-rename data and log directories"
  fi
  echo "    $DATA, $LOGS and the OAuth token were not touched — they belong to the current install"
elif [ "$PURGE" = 1 ]; then
  run rm -rf "$DATA" "$LOGS" "$LEGACY_DATA" "$LEGACY_LOGS" "$REPO/.secrets/token.json"
  if [ "$DRY" = 1 ]; then
    echo "==> would purge cached events, sync state, logs, and the OAuth token"
  else
    echo "==> purged cached events, sync state, logs, and the OAuth token"
  fi
  echo "    the OAuth client ($REPO/.secrets/oauth-client.json) is kept; delete it by hand if you want it gone"
  echo "    revoke the Google grant at https://myaccount.google.com/permissions"
elif [ "$LEGACY_ONLY" = 1 ]; then
  if [ -d "$LEGACY_DATA" ] || [ -d "$LEGACY_LOGS" ]; then
    echo "==> kept $LEGACY_DATA and $LEGACY_LOGS — add --purge to remove them"
  fi
else
  echo "==> kept $DATA, $LOGS, and .secrets/ — re-run uninstall.sh --purge to remove them"
  if [ -d "$LEGACY_DATA" ] || [ -d "$LEGACY_LOGS" ]; then
    echo "    a pre-rename $LEGACY_DATA / $LEGACY_LOGS is still there too; --purge removes those as well"
  fi
fi

echo "==> synced notes were not touched"
