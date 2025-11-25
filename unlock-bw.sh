#!/bin/bash

# =============================================================================
# Bitwarden CLI Helper - Enhanced Password Manager
# =============================================================================
# Features:
#   - Session caching (avoids repeated unlocks)
#   - TOTP code support
#   - Multiple field types (password, username, uri, notes, totp)
#   - Clipboard auto-clear for security
#   - Interactive fuzzy search with preview
#   - Desktop notifications
#   - Sync support
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
PASSWORD_FILE="$HOME/.bw_password"
SESSION_FILE="$HOME/.bw_session"
SESSION_TIMEOUT=3600  # 1 hour in seconds
CLIPBOARD_CLEAR_SECONDS=30
NOTIFY_ENABLED=true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

notify() {
  if $NOTIFY_ENABLED && command -v notify-send &>/dev/null; then
    notify-send "Bitwarden" "$1" --icon=dialog-password 2>/dev/null || true
  fi
}

usage() {
  cat <<EOF
${CYAN}Bitwarden CLI Helper${NC}

${YELLOW}Usage:${NC}
  $(basename "$0") <search_term> [field]    Search and copy credential
  $(basename "$0") --totp <search_term>     Copy TOTP code
  $(basename "$0") --show <search_term>     Show item details (no copy)
  $(basename "$0") --sync                   Sync vault with server
  $(basename "$0") --lock                   Lock the vault
  $(basename "$0") --status                 Check vault status
  $(basename "$0") --help                   Show this help

${YELLOW}Fields:${NC}
  password  (default)  Copy password
  username            Copy username
  uri                 Copy first URI
  notes               Copy notes
  totp                Copy TOTP code

${YELLOW}Examples:${NC}
  $(basename "$0") github                   # Copy github password
  $(basename "$0") github username          # Copy github username
  $(basename "$0") --totp github            # Copy github 2FA code
  $(basename "$0") --show aws               # View aws item details

${YELLOW}Setup:${NC}
  Create ${PASSWORD_FILE} with your master password.
  chmod 600 ${PASSWORD_FILE}

EOF
  exit 0
}

# -----------------------------------------------------------------------------
# Session Management
# -----------------------------------------------------------------------------
is_session_valid() {
  if [[ ! -f "$SESSION_FILE" ]]; then
    return 1
  fi

  # Check file age
  local file_age=$(( $(date +%s) - $(stat -c %Y "$SESSION_FILE") ))
  if (( file_age > SESSION_TIMEOUT )); then
    rm -f "$SESSION_FILE"
    return 1
  fi

  # Load and verify session
  local session
  session=$(cat "$SESSION_FILE")
  if BW_SESSION="$session" bw unlock --check &>/dev/null; then
    export BW_SESSION="$session"
    return 0
  fi

  rm -f "$SESSION_FILE"
  return 1
}

ensure_unlocked() {
  # Try existing session first
  if is_session_valid; then
    return 0
  fi

  # Need to unlock
  if [[ ! -f "$PASSWORD_FILE" ]]; then
    error "Password file not found: $PASSWORD_FILE"
    echo "Create it with: echo 'your_master_password' > $PASSWORD_FILE && chmod 600 $PASSWORD_FILE"
    exit 1
  fi

  info "Unlocking Bitwarden..."
  local output
  output=$(bw unlock --passwordfile "$PASSWORD_FILE" 2>&1) || {
    error "Failed to unlock. Check your master password."
    exit 1
  }

  if echo "$output" | grep -q 'export BW_SESSION'; then
    local session_key
    session_key=$(echo "$output" | grep 'export BW_SESSION' | sed 's/.*export BW_SESSION="//;s/".*//')
    export BW_SESSION="$session_key"

    # Cache session
    echo "$session_key" > "$SESSION_FILE"
    chmod 600 "$SESSION_FILE"

    success "Vault unlocked (session cached for ${SESSION_TIMEOUT}s)"
  else
    error "Could not extract session key"
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# Clipboard Functions
# -----------------------------------------------------------------------------
copy_to_clipboard() {
  local content="$1"
  local field_name="${2:-value}"

  if command -v wl-copy &>/dev/null; then
    echo -n "$content" | wl-copy
  elif command -v xclip &>/dev/null; then
    echo -n "$content" | xclip -selection clipboard
  else
    error "No clipboard tool found (need wl-copy or xclip)"
    exit 1
  fi

  success "$field_name copied to clipboard"
  notify "$field_name copied to clipboard"

  # Schedule clipboard clear
  if (( CLIPBOARD_CLEAR_SECONDS > 0 )); then
    info "Clipboard will clear in ${CLIPBOARD_CLEAR_SECONDS}s"
    (
      sleep "$CLIPBOARD_CLEAR_SECONDS"
      if command -v wl-copy &>/dev/null; then
        echo -n "" | wl-copy
      elif command -v xclip &>/dev/null; then
        echo -n "" | xclip -selection clipboard
      fi
    ) &>/dev/null &
    disown
  fi
}

# -----------------------------------------------------------------------------
# Item Selection
# -----------------------------------------------------------------------------
select_item() {
  local search_term="$1"

  info "Searching for '$search_term'..."
  local items
  items=$(bw list items --search "$search_term" 2>/dev/null)

  if [[ -z "$items" || "$items" == "[]" ]]; then
    error "No items found for '$search_term'"
    exit 1
  fi

  local count
  count=$(echo "$items" | jq 'length')

  if (( count == 1 )); then
    # Single match - use it directly
    echo "$items" | jq -r '.[0].id'
    return 0
  fi

  # Multiple matches - show picker
  local item_list
  item_list=$(echo "$items" | jq -r '.[] | "\(.id)\t\(.name)\t\(.login.username // "-")"')

  local selected
  if command -v fzf &>/dev/null; then
    selected=$(echo "$item_list" | fzf \
      --delimiter='\t' \
      --with-nth=2,3 \
      --header="Select item (${count} matches)" \
      --preview="echo 'Name: {2}'; echo 'User: {3}'" \
      --preview-window=up:2 \
      | cut -f1)
  elif command -v wofi &>/dev/null; then
    local display_list
    display_list=$(echo "$items" | jq -r '.[] | "\(.id) │ \(.name) │ \(.login.username // "-")"')
    selected=$(echo "$display_list" | wofi --dmenu --prompt "Select item:" | cut -d'│' -f1 | tr -d ' ')
  elif command -v rofi &>/dev/null; then
    local display_list
    display_list=$(echo "$items" | jq -r '.[] | "\(.id) │ \(.name) │ \(.login.username // "-")"')
    selected=$(echo "$display_list" | rofi -dmenu -p "Select item:" | cut -d'│' -f1 | tr -d ' ')
  else
    error "No picker available (need fzf, wofi, or rofi)"
    exit 1
  fi

  if [[ -z "$selected" ]]; then
    error "No item selected"
    exit 1
  fi

  echo "$selected"
}

# -----------------------------------------------------------------------------
# Commands
# -----------------------------------------------------------------------------
cmd_get() {
  local search_term="$1"
  local field="${2:-password}"

  ensure_unlocked
  local item_id
  item_id=$(select_item "$search_term")

  local result
  if [[ "$field" == "totp" ]]; then
    result=$(bw get totp "$item_id" 2>/dev/null) || {
      error "No TOTP configured for this item"
      exit 1
    }
  else
    result=$(bw get "$field" "$item_id" 2>/dev/null) || {
      error "Failed to get $field"
      exit 1
    }
  fi

  copy_to_clipboard "$result" "$field"
}

cmd_totp() {
  local search_term="$1"
  cmd_get "$search_term" "totp"
}

cmd_show() {
  local search_term="$1"

  ensure_unlocked
  local item_id
  item_id=$(select_item "$search_term")

  local item
  item=$(bw get item "$item_id" 2>/dev/null)

  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Name:${NC}     $(echo "$item" | jq -r '.name')"
  echo -e "${YELLOW}Username:${NC} $(echo "$item" | jq -r '.login.username // "N/A"')"
  echo -e "${YELLOW}Password:${NC} $(echo "$item" | jq -r '.login.password // "N/A" | if . == "N/A" then . else "••••••••" end')"

  local uris
  uris=$(echo "$item" | jq -r '.login.uris[]?.uri // empty' 2>/dev/null)
  if [[ -n "$uris" ]]; then
    echo -e "${YELLOW}URIs:${NC}"
    echo "$uris" | while read -r uri; do
      echo "          $uri"
    done
  fi

  local has_totp
  has_totp=$(echo "$item" | jq -r '.login.totp // empty')
  if [[ -n "$has_totp" ]]; then
    echo -e "${YELLOW}TOTP:${NC}     ${GREEN}Configured${NC}"
  fi

  local notes
  notes=$(echo "$item" | jq -r '.notes // empty')
  if [[ -n "$notes" ]]; then
    echo -e "${YELLOW}Notes:${NC}"
    echo "$notes" | sed 's/^/          /'
  fi
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

cmd_sync() {
  ensure_unlocked
  info "Syncing vault..."
  bw sync
  success "Vault synced"
  notify "Vault synced"
}

cmd_lock() {
  bw lock &>/dev/null || true
  rm -f "$SESSION_FILE"
  success "Vault locked"
  notify "Vault locked"
}

cmd_status() {
  echo -e "${CYAN}Bitwarden Status${NC}"
  echo ""

  if is_session_valid; then
    echo -e "Session: ${GREEN}Active${NC}"
    local file_age=$(( $(date +%s) - $(stat -c %Y "$SESSION_FILE") ))
    local remaining=$(( SESSION_TIMEOUT - file_age ))
    echo -e "Expires: ${remaining}s"
  else
    echo -e "Session: ${YELLOW}Locked${NC}"
  fi

  echo ""
  bw status 2>/dev/null | jq -r '"Server: \(.serverUrl // "Default")\nEmail: \(.userEmail // "Unknown")"' || true
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  case "${1:-}" in
    -h|--help|help)
      usage
      ;;
    --sync|sync)
      cmd_sync
      ;;
    --lock|lock)
      cmd_lock
      ;;
    --status|status)
      cmd_status
      ;;
    --totp)
      [[ -z "${2:-}" ]] && { error "Search term required"; exit 1; }
      cmd_totp "$2"
      ;;
    --show|show)
      [[ -z "${2:-}" ]] && { error "Search term required"; exit 1; }
      cmd_show "$2"
      ;;
    "")
      usage
      ;;
    *)
      cmd_get "$1" "${2:-password}"
      ;;
  esac
}

main "$@"
