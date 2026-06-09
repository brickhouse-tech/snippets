#!/usr/bin/env bash
#
# reset-contacts-addressbook.sh
#
# Nukes the local macOS Contacts (AddressBook) state to fix a corrupted /
# stale Contacts.app caused by bad Cloud Library / AddressBook caching.
#
# It quits Contacts and its helpers, finds every AddressBook-related item
# under the standard ~/Library locations, SHOWS you exactly what it found,
# asks for confirmation, backs everything up to a timestamped tarball, then
# deletes it and flushes the prefs cache.
#
# It does NOT touch iCloud settings (Apple locks that down to scripts). After
# running, you still need to: System Settings > Apple ID > iCloud > uncheck
# Contacts, then restart your Mac. The script prints these reminders at the end.
#
# Usage:
#   reset-contacts-addressbook.sh [options]
#
# Options:
#   -n, --dry-run     Show what would be deleted; make no changes. (safest)
#   -y, --yes         Skip the interactive confirmation prompt.
#   -B, --no-backup   Do NOT create a backup tarball before deleting.
#   -h, --help        Show this help.
#
# Exit codes: 0 ok, 1 error/aborted.

set -euo pipefail

# ---------------------------------------------------------------------------
# config / globals
# ---------------------------------------------------------------------------

# Case-insensitive token every target path/file must contain.
readonly MATCH_TOKEN="addressbook"

# Library roots to scan. Globs are expanded at scan time.
LIBRARY_ROOTS=(
  "${HOME}/Library/Containers"
  "${HOME}/Library/Group Containers"
  "${HOME}/Library/Application Support"
  "${HOME}/Library/Preferences"
  "${HOME}/Library/Caches"
  "${HOME}/Library/HTTPStorages"
  "${HOME}/Library/Saved Application State"
)

# Processes to terminate before touching files.
APPS_TO_QUIT=(
  "Contacts"
  "AddressBookSourceSync"
  "AddressBookManager"
  "ContactsAccountsService"
  "AddressBookSync"
)

# Where backups land (outside ~/Library so we never re-scan our own backup).
BACKUP_DIR="${HOME}/.cache/reset-contacts-addressbook"

# runtime flags
DRY_RUN=false
ASSUME_YES=false
DO_BACKUP=true

# discovered targets (filled by collect_targets)
TARGETS=()

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

log()  { printf '%s\n' "$*"; }
info() { printf '\033[36m• %s\033[0m\n' "$*"; }
warn() { printf '\033[33m! %s\033[0m\n' "$*" >&2; }
err()  { printf '\033[31mx %s\033[0m\n' "$*" >&2; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$*"; }

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
}

# Timestamp without relying on a hardcoded locale.
timestamp() { date +%Y%m%d%H%M%S; }

# ---------------------------------------------------------------------------
# argument parsing (supports flags in any order)
# ---------------------------------------------------------------------------

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--dry-run)   DRY_RUN=true ;;
      -y|--yes)       ASSUME_YES=true ;;
      -B|--no-backup) DO_BACKUP=false ;;
      -h|--help)      usage; exit 0 ;;
      --)             shift; break ;;
      -*)             err "Unknown option: $1"; usage; exit 1 ;;
      *)              err "Unexpected argument: $1"; usage; exit 1 ;;
    esac
    shift
  done
}

# ---------------------------------------------------------------------------
# discovery: find every AddressBook-related path under the library roots
# ---------------------------------------------------------------------------

collect_targets() {
  local root entry base
  for root in "${LIBRARY_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    # Match only top-level entries inside each root (don't recurse into
    # unrelated containers); the AddressBook artifacts live one level down.
    for entry in "$root"/*; do
      [[ -e "$entry" ]] || continue
      base="$(basename "$entry")"
      # case-insensitive contains MATCH_TOKEN
      if [[ "$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')" == *"${MATCH_TOKEN}"* ]]; then
        TARGETS+=("$entry")
      fi
    done
  done
}

# ---------------------------------------------------------------------------
# preview + confirm
# ---------------------------------------------------------------------------

show_targets() {
  if [[ ${#TARGETS[@]} -eq 0 ]]; then
    ok "Nothing to do — no AddressBook artifacts found."
    return 1
  fi

  log ""
  warn "The following ${#TARGETS[@]} item(s) will be DELETED:"
  log ""
  local t size
  for t in "${TARGETS[@]}"; do
    size="$(du -sh "$t" 2>/dev/null | cut -f1)"
    printf '   %-6s %s\n' "${size:-?}" "$t"
  done
  log ""
  return 0
}

confirm() {
  $ASSUME_YES && return 0
  local reply
  printf '\033[33mProceed with deletion? Type "yes" to continue: \033[0m'
  read -r reply
  [[ "$reply" == "yes" ]]
}

# ---------------------------------------------------------------------------
# actions
# ---------------------------------------------------------------------------

quit_apps() {
  info "Quitting Contacts and AddressBook helper processes…"
  # Graceful quit of the GUI app first.
  if pgrep -x "Contacts" >/dev/null 2>&1; then
    osascript -e 'tell application "Contacts" to quit' >/dev/null 2>&1 || true
    sleep 1
  fi
  local app
  for app in "${APPS_TO_QUIT[@]}"; do
    if pgrep -x "$app" >/dev/null 2>&1; then
      killall "$app" >/dev/null 2>&1 || true
    fi
  done
}

backup_targets() {
  $DO_BACKUP || { warn "Skipping backup (--no-backup)."; return 0; }
  mkdir -p "$BACKUP_DIR"
  local archive="${BACKUP_DIR}/addressbook-backup-$(timestamp).tar.gz"
  info "Backing up to: ${archive}"
  # -C / with absolute members stripped keeps the archive portable.
  if tar -czf "$archive" -C / "${TARGETS[@]#/}" 2>/dev/null; then
    ok "Backup created ($(du -sh "$archive" 2>/dev/null | cut -f1))."
  else
    err "Backup failed — aborting before any deletion."
    return 1
  fi
}

delete_targets() {
  info "Deleting AddressBook artifacts…"
  local t
  for t in "${TARGETS[@]}"; do
    rm -rf -- "$t" && ok "removed ${t}" || warn "could not remove ${t}"
  done
  # Flush the cached preferences daemon so deleted plists don't get rewritten.
  killall cfprefsd >/dev/null 2>&1 || true
}

print_followup() {
  log ""
  warn "Manual steps still required (cannot be scripted safely):"
  log "   1. System Settings → [your name] → iCloud → uncheck/disable Contacts."
  log "      (opening the pane for you…)"
  open "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane" 2>/dev/null || true
  log "   2. Restart your Mac."
  log "   3. Re-open Contacts; if using iCloud, re-enable Contacts in iCloud after reboot."
  if $DO_BACKUP; then
    log ""
    info "A backup of everything removed is in: ${BACKUP_DIR}"
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

main() {
  parse_args "$@"

  info "Scanning for AddressBook artifacts under ~/Library …"
  collect_targets

  show_targets || exit 0   # nothing found → clean exit

  if $DRY_RUN; then
    warn "Dry run (--dry-run): no changes made."
    exit 0
  fi

  confirm || { err "Aborted by user."; exit 1; }

  quit_apps
  backup_targets || exit 1
  delete_targets
  print_followup

  log ""
  ok "Done. Restart your Mac to finish the reset."
}

# Run main only when executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
