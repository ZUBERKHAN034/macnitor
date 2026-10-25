#!/bin/zsh
#
# Removes Macnitor and everything it stored on this Mac.
#
#     ./scripts/uninstall.sh          # asks first, lists what it will delete
#     ./scripts/uninstall.sh --yes    # no prompt
#
# Deleting Macnitor.app on its own leaves your settings behind, which is why a
# reinstall skips onboarding — macOS keeps preferences and containers when an
# app goes to the Trash. This removes those too, so a reinstall starts clean.
#
# Macnitor installs no helper tool or LaunchDaemon. If the optional Terminal
# command was installed, macOS may ask for administrator permission to remove
# its symbolic link from /usr/local/bin.
set -euo pipefail

assume_yes=0
[[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && assume_yes=1

app="/Applications/Macnitor.app"
previous_app="/Applications/Macitor.app"
older_app="/Applications/Mactrics.app"
legacy_app="/Applications/Mectrics.app"
cli_link="/usr/local/bin/macnitor"
previous_cli_link="/usr/local/bin/macitor"
older_cli_link="/usr/local/bin/mactrics"
legacy_cli_link="/usr/local/bin/mectrics"
targets=(
  "$app"
  "$previous_app"
  "$older_app"
  "$legacy_app"
  "$HOME/Library/Preferences/com.mectrics.app.plist"
  "$HOME/Library/Group Containers/group.com.mectrics.app"
  "$HOME/Library/Containers/com.mectrics.app.widget"
  "$HOME/Library/Application Support/Macnitor"
  "$HOME/Library/Application Support/Macitor"
  "$HOME/Library/Application Support/Mactrics"
  "$HOME/Library/Application Support/Mectrics"
  "$HOME/Library/Caches/com.mectrics.app"
  "$HOME/Library/Caches/com.mectrics.app.sparkle"
  "$HOME/Library/HTTPStorages/com.mectrics.app"
  "$HOME/Library/Saved Application State/com.mectrics.app.savedState"
)

if [[ -L "$cli_link" ]]; then
  cli_target="$(readlink "$cli_link")"
  if [[ "$cli_target" == */Macnitor.app/Contents/Helpers/macnitor \
     || "$cli_target" == */Macitor.app/Contents/Helpers/macitor \
     || "$cli_target" == */Mactrics.app/Contents/Helpers/mactrics \
     || "$cli_target" == */Mectrics.app/Contents/Helpers/mectrics ]]; then
    targets+=("$cli_link")
  fi
fi
if [[ -L "$previous_cli_link" ]]; then
  cli_target="$(readlink "$previous_cli_link")"
  if [[ "$cli_target" == */Macnitor.app/Contents/Helpers/macnitor \
     || "$cli_target" == */Macitor.app/Contents/Helpers/macitor \
     || "$cli_target" == */Mactrics.app/Contents/Helpers/mactrics \
     || "$cli_target" == */Mectrics.app/Contents/Helpers/mectrics ]]; then
    targets+=("$previous_cli_link")
  fi
fi
if [[ -L "$older_cli_link" ]]; then
  cli_target="$(readlink "$older_cli_link")"
  if [[ "$cli_target" == */Macnitor.app/Contents/Helpers/macnitor \
     || "$cli_target" == */Macitor.app/Contents/Helpers/macitor \
     || "$cli_target" == */Mactrics.app/Contents/Helpers/mactrics \
     || "$cli_target" == */Mectrics.app/Contents/Helpers/mectrics ]]; then
    targets+=("$older_cli_link")
  fi
fi
if [[ -L "$legacy_cli_link" ]]; then
  cli_target="$(readlink "$legacy_cli_link")"
  if [[ "$cli_target" == */Mectrics.app/Contents/Helpers/mectrics \
     || "$cli_target" == */Mactrics.app/Contents/Helpers/mactrics \
     || "$cli_target" == */Macitor.app/Contents/Helpers/macitor \
     || "$cli_target" == */Macnitor.app/Contents/Helpers/macnitor ]]; then
    targets+=("$legacy_cli_link")
  fi
fi

present=()
for t in "${targets[@]}"; do
  [[ -e "$t" ]] && present+=("$t")
done

if (( ${#present[@]} == 0 )); then
  echo "Nothing to remove — Macnitor is not installed and left no data."
  exit 0
fi

echo "This will delete:"
printf '  %s\n' "${present[@]}"
echo
echo "Your Attention Log and any saved diagnostics are included. Copy them first"
echo "if you want to keep them."

if (( ! assume_yes )); then
  echo
  printf "Continue? [y/N] "
  read -r reply
  [[ "$reply" == [yY] ]] || { echo "Cancelled."; exit 1; }
fi

# Quit first. A running Macnitor writes its preferences on the way out, which
# would put the file straight back after it was deleted.
osascript -e 'quit app "Macnitor"' 2>/dev/null || true
osascript -e 'quit app "Macitor"' 2>/dev/null || true
osascript -e 'quit app "Mactrics"' 2>/dev/null || true
osascript -e 'quit app "Mectrics"' 2>/dev/null || true
for _ in 1 2 3 4 5; do
  pgrep -x Macnitor >/dev/null 2>&1 || pgrep -x Macitor >/dev/null 2>&1 \
    || pgrep -x Mactrics >/dev/null 2>&1 \
    || pgrep -x Mectrics >/dev/null 2>&1 || break
  sleep 1
done
pkill -x Macnitor 2>/dev/null || true
pkill -x Macitor 2>/dev/null || true
pkill -x Mactrics 2>/dev/null || true
pkill -x Mectrics 2>/dev/null || true
pkill -f 'MacnitorWidget.appex' 2>/dev/null || true
pkill -f 'MactricsWidget.appex' 2>/dev/null || true
pkill -f 'MectricsWidget.appex' 2>/dev/null || true

# Preferences live in cfprefsd's cache as well as on disk, so remove the domain
# through defaults before unlinking the file.
defaults delete com.mectrics.app 2>/dev/null || true

# One protected path must not abandon the rest, so each target is its own attempt.
# ~/Library/Containers belongs to containermanagerd: removing the widget's sandbox
# is refused unless the caller holds Full Disk Access, and that is not worth asking
# for to delete one JSON snapshot.
failed=()
for t in "${present[@]}"; do
  if [[ "$t" == "$cli_link" || "$t" == "$previous_cli_link" \
     || "$t" == "$older_cli_link" || "$t" == "$legacy_cli_link" ]]; then
    rm -f "$t" 2>/dev/null \
      || sudo rm -f "$t" \
      || failed+=("$t")
  else
    rm -rf "$t" 2>/dev/null || failed+=("$t")
  fi
done

echo
if (( ${#failed[@]} == 0 )); then
  echo "Removed. Macnitor left no command links, helper tools, daemons, or files elsewhere."
else
  echo "Removed everything except:"
  printf '  %s\n' "${failed[@]}"
  echo
  echo "macOS protects those paths from the command line. Drag them to the Trash in"
  echo "Finder (⇧⌘G to paste the path), or leave them — they hold nothing but a cached"
  echo "snapshot, and macOS reclaims the container once the extension is gone."
fi

echo
echo "If you had turned on Launch at login, macOS may still list a stale entry"
echo "under System Settings → General → Login Items. Removing it there is the"
echo "last step; an app cannot unregister itself once it has been deleted."
