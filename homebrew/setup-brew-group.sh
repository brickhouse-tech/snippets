#!/usr/bin/env bash
set -euo pipefail

# setup-brew-group.sh — Configure Homebrew for shared group access (no sudo needed for brew)
# Usage: sudo ./setup-brew-group.sh [GROUP]
# Default group: developer

GROUP="${1:-developer}"
BREW_PREFIX="$(brew --prefix 2>/dev/null || echo "/opt/homebrew")"

# --- Preflight ---

if [[ $EUID -ne 0 ]]; then
  echo "Error: Must run as root (sudo)." >&2
  exit 1
fi

if ! dseditgroup -o read "$GROUP" &>/dev/null; then
  echo "Error: Group '$GROUP' does not exist." >&2
  echo "Create it with: sudo dseditgroup -o create $GROUP" >&2
  exit 1
fi

if [[ ! -d "$BREW_PREFIX" ]]; then
  echo "Error: Homebrew prefix '$BREW_PREFIX' not found." >&2
  exit 1
fi

echo "Homebrew prefix: $BREW_PREFIX"
echo "Group: $GROUP"
echo ""

# --- 1. Set group ownership ---
echo "→ Setting group ownership to '$GROUP'..."
chgrp -R "$GROUP" "$BREW_PREFIX"

# --- 2. Make everything group-writable ---
echo "→ Making everything group-writable..."
chmod -R g+w "$BREW_PREFIX"

# --- 3. Set setgid on all directories ---
echo "→ Setting setgid bit on directories (new files inherit group)..."
find "$BREW_PREFIX" -type d -exec chmod g+ws {} +

# --- 4. Strip com.apple.provenance xattr ---
echo "→ Stripping com.apple.provenance extended attributes..."
xattr -r -d com.apple.provenance "$BREW_PREFIX" 2>/dev/null || true

# --- 5. Fix /private/tmp permissions ---
echo "→ Ensuring /private/tmp is world-writable with sticky bit..."
chmod 1777 /private/tmp

# --- 6. Handle Homebrew's Git repository separately if it's a different path ---
BREW_REPO="$(brew --repository 2>/dev/null || echo "$BREW_PREFIX")"
if [[ "$BREW_REPO" != "$BREW_PREFIX" && -d "$BREW_REPO" ]]; then
  echo "→ Fixing Homebrew repository at $BREW_REPO..."
  chgrp -R "$GROUP" "$BREW_REPO"
  chmod -R g+w "$BREW_REPO"
  find "$BREW_REPO" -type d -exec chmod g+ws {} +
  xattr -r -d com.apple.provenance "$BREW_REPO" 2>/dev/null || true
fi

echo ""
echo "✓ Done. Homebrew is now accessible to all members of '$GROUP'."
echo ""
echo "Remaining steps for each user:"
echo "  1. Verify group membership: id | grep $GROUP"
echo "  2. Add to ~/.zshrc:"
echo "     umask 002"
echo "     export HOMEBREW_NO_QUARANTINE=1"
echo "  3. Log out and back in for group changes to take effect"
