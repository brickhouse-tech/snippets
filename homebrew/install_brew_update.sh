#!/usr/bin/env bash
set -euo pipefail

# Determine the full path to this script (works in bash)
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
	DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
	SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
	[[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$SCRIPT_SOURCE")"

BREW_UPDATE_SH_PATH="$SCRIPT_PATH"

# Locate the plist template (assumed next to this script)
TEMPLATE_PLIST_PATH="$SCRIPT_DIR/com.user.brew_upgrade.plist"

if [ ! -f "$TEMPLATE_PLIST_PATH" ]; then
  echo "Plist template not found at: $TEMPLATE_PLIST_PATH" >&2
  exit 1
fi

# We're installing a system-wide LaunchDaemon only; per-user LaunchAgent logic removed.

# Install as a system-wide LaunchDaemon so it runs at boot for all users
# This requires sudo and will place the plist in /Library/LaunchDaemons
SYSTEM_DEST_DIR="/Library/LaunchDaemons"
SYSTEM_DEST_PLIST="$SYSTEM_DEST_DIR/com.user.brew_upgrade.plist"

TMP_PLIST="$(mktemp -t com.user.brew_upgrade.plist.XXXX)"
awk -v p="$BREW_UPDATE_SH_PATH" '{gsub(/\$\{BREW_UPDATE_SH_PATH\}/, p); print}' "$TEMPLATE_PLIST_PATH" > "$TMP_PLIST"

echo "Installing system LaunchDaemon to: $SYSTEM_DEST_PLIST (requires sudo)"
sudo cp "$TMP_PLIST" "$SYSTEM_DEST_PLIST"
sudo chown root:wheel "$SYSTEM_DEST_PLIST"
sudo chmod 644 "$SYSTEM_DEST_PLIST"
rm -f "$TMP_PLIST"

# Unload existing system daemon if present, then bootstrap
set +e
sudo launchctl bootout system "$SYSTEM_DEST_PLIST" 2>/dev/null
set -e

echo "Bootstrapping system LaunchDaemon..."
sudo launchctl bootstrap system "$SYSTEM_DEST_PLIST"

echo "Installed and launched system LaunchDaemon: $SYSTEM_DEST_PLIST"

