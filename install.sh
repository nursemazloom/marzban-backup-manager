#!/usr/bin/env bash
# ============================================================
# Marzban Backup Manager (MBM) — All-in-One (install.sh == mbm)
# Version: 1.1.0
# ============================================================
set -euo pipefail

VERSION="1.1.0"

# ===== Paths =====
APP_DIR="/opt/marzban-backup"
CONF="$APP_DIR/config.conf"
CRON_TAG="# mbm-backup"
REPO_RAW_BASE="https://raw.githubusercontent.com/nursemazloom/marzban-backup-manager/main"
REMOTE_SCRIPT="$REPO_RAW_BASE/install.sh"
MBM_BIN="/usr/local/bin/mbm"
CRON_LOG="$APP_DIR/cron.log"
BACKUP_DIR="$APP_DIR/backups"

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"

# ===== Colors =====
RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[0;33m'; CYN=$'\033[0;36m'
MAG=$'\033[0;35m'; WHT=$'\033[1;37m'; NC=$'\033[0m'
say(){  echo -e "${CYN}➜${NC} $*"; }
ok(){   echo -e "${GRN}✔${NC} $*"; }
warn(){ echo -e "${YLW}⚠${NC} $*"; }
err(){  echo -e "${RED}✖${NC} $*"; }

title(){
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${WHT}$*${NC}"
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ===== TTY-safe read (works in cron/pipes too) =====
read_tty(){
  local __var="$1"
  local __prompt="${2:-}"
  local __val=""
  if [ -n "$__prompt" ]; then
    echo -ne "$__prompt" >/dev/tty 2>/dev/null || echo -ne "$__prompt"
  fi
  if [ -c /dev/tty ]; then
    IFS= read -r __val </dev/tty || true
  else
    IFS= read -r __val || true
  fi
  printf -v "$__var" "%s" "$__val"
}

# ===== marzban binary (robust) =====
detect_marzban(){
  local m=""
  m="$(command -v marzban 2>/dev/null || true)"
  [ -z "$m" ] && [ -x /usr/local/bin/marzban ] && m="/usr/local/bin/marzban"
  [ -z "$m" ] && [ -x /usr/bin/marzban ] && m="/usr/bin/marzban"
  echo "$m"
}
MARZBAN_BIN="$(detect_marzban)"

# ============================================================
# HELP
# ============================================================
help(){
  title "Marzban Backup Manager (mbm)  v${VERSION}"
  echo -e "${CYN}Usage:${NC}  mbm <command>\n"
  echo -e "${YLW}Commands:${NC}"
  printf "  ${WHT}%-12s${NC} | %s\n" "install"   "Setup Telegram + Proxy + Schedule (runs first backup)"
  printf "  ${WHT}%-12s${NC} | %s\n" "backup"    "Create backup now and send to Telegram"
  printf "  ${WHT}%-12s${NC} | %s\n" "restore"   "Interactive restore (asks backup path and confirmation)"
  printf "  ${WHT}%-12s${NC} | %s\n" "status"    "Show mbm + cron + last backup status"
  printf "  ${WHT}%-12s${NC} | %s\n" "version"   "Show version"
  printf "  ${WHT}%-12s${NC} | %s\n" "update"    "Update mbm from GitHub (keeps config)"
  printf "  ${WHT}%-12s${NC} | %s\n" "uninstall" "Remove mbm + cron + config"
  printf "  ${WHT}%-12s${NC} | %s\n" "help"      "Show this help"
  echo
  echo -e "${YLW}Proxy formats (optional):${NC}"
  echo "  socks5h://127.0.0.1:1080   (recommended for Iran)"
  echo "  socks5://127.0.0.1:1080"
  echo "  127.0.0.1:1080"
}

# ============================================================
# SERVER IP
# ============================================================
get_server_ip(){
  local ip=""
  ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}' || true)"
  [ -n "$ip" ] && { echo "$ip"; return 0; }
  ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  [ -n "$ip" ] && { echo "$ip"; return 0; }
  ip="$(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
  echo "${ip:-unknown}"
}

# ============================================================
# DEPENDENCIES
# ============================================================
install_deps(){
  say "Installing dependencies..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y curl cron python3 python3-pip tar gzip iproute2 ca-certificates >/dev/null 2>&1 || true
  systemctl enable --now cron >/dev/null 2>&1 || true

  if python3 -c "import jdatetime" >/dev/null 2>&1; then
    ok "jdatetime already available"
    return
  fi

  apt-get install -y python3-jdatetime >/dev/null 2>&1 || true
  if python3 -c "import jdatetime" >/dev/null 2>&1; then
    ok "Installed jdatetime via apt"
    return
  fi

  python3 -m pip install -q --upgrade pip >/dev/null 2>&1 || true
  python3 -m pip install -q jdatetime --break-system-packages >/dev/null 2>&1 || \
  python3 -m pip install -q --user jdatetime >/dev/null 2>&1 || true

  if python3 -c "import jdatetime" >/dev/null 2>&1; then
    ok "Installed jdatetime via pip"
  else
    warn "Could not auto-install jdatetime (Jalali timestamps may not work)"
  fi
}

ensure_deps(){
  mkdir -p "$BACKUP_DIR" "$APP_DIR"
  command -v curl >/dev/null 2>&1 || install_deps
  command -v python3 >/dev/null 2>&1 || install_deps
  command -v tar >/dev/null 2>&1 || install_deps
  python3 -c "import jdatetime" >/dev/null 2>&1 || install_deps
}

# ============================================================
# CONFIG
# ============================================================
save_conf(){
  mkdir -p "$APP_DIR"
  cat > "$CONF" <<CFG
TOKEN="$TOKEN"
CHAT_ID="$CHAT_ID"
PROXY="$PROXY"
INTERVAL_MINUTES="$INTERVAL_MINUTES"
MAX_BACKUPS="$MAX_BACKUPS"
CFG
  chmod 600 "$CONF" || true
}

load_conf(){
  [ -f "$CONF" ] || { err "Not installed. Run: mbm install"; exit 1; }
  # shellcheck disable=SC1090
  source "$CONF"
}

# ============================================================
# CRON
# - <60 min: */M
# - >=60: round down to whole hours (cron limitation)
# ============================================================
cron_expr_from_minutes(){
  local M="$1"
  if ! [[ "$M" =~ ^[0-9]+$ ]] || [ "$M" -lt 1 ]; then echo ""; return; fi
  if [ "$M" -lt 60 ]; then echo "*/$M * * * *"; return; fi

  local H=$(( M / 60 ))
  local R=$(( M % 60 ))
  if [ "$H" -lt 1 ]; then H=1; fi
  if [ "$R" -ne 0 ]; then
    warn "Interval ${M}min is not multiple of 60. Using ${H}h ($((H*60))min)."
  fi

  if [ "$H" -ge 24 ]; then
    local D=$(( H / 24 ))
    [ "$D" -lt 1 ] && D=1
    echo "0 0 */$D * *"
  else
    echo "0 */$H * * *"
  fi
}

setup_cron(){
  local expr
  expr="$(cron_expr_from_minutes "$INTERVAL_MINUTES")"
  [ -n "$expr" ] || { err "Invalid interval. Enter minutes >= 1"; exit 1; }

  crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab - 2>/dev/null || true
  ( crontab -l 2>/dev/null; echo "$expr $MBM_BIN backup >>$CRON_LOG 2>&1 $CRON_TAG" ) | crontab -
  ok "Cron set: $expr"
}

# ============================================================
# JALALI TIMESTAMP
# ============================================================
jalali_stamp(){
  python3 - <<'PY'
from datetime import datetime
import jdatetime
print(jdatetime.datetime.fromgregorian(datetime=datetime.now()).strftime("%Y-%m-%d_%H-%M-%S"))
PY
}
jalali_human(){
  python3 - <<'PY'
from datetime import datetime
import jdatetime
print(jdatetime.datetime.fromgregorian(datetime=datetime.now()).strftime("%Y-%m-%d %H:%M:%S"))
PY
}

# ============================================================
# PROXY
# ============================================================
proxy_try(){
  local p="$1"
  curl --proxy "$p" -I -s --max-time 10 https://api.telegram.org >/dev/null 2>&1
}

validate_proxy(){
  while true; do
    echo
    echo -e "${WHT}SOCKS5 Proxy (optional)${NC}"
    echo "Formats:"
    echo "  socks5h://127.0.0.1:1080"
    echo "  socks5://127.0.0.1:1080"
    echo "  127.0.0.1:1080"
    echo "Leave empty if not needed:"
    read_tty INPUT ""

    if [ -z "${INPUT:-}" ]; then PROXY=""; return; fi
    if [[ "$INPUT" =~ ^http ]]; then err "Invalid format (only socks5/socks5h)"; continue; fi

    local base=""
    if [[ "$INPUT" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
      base="$INPUT"
    elif [[ "$INPUT" =~ ^socks5h:// ]]; then
      base="${INPUT#socks5h://}"
    elif [[ "$INPUT" =~ ^socks5:// ]]; then
      base="${INPUT#socks5://}"
    else
      err "Invalid format."
      continue
    fi

    local c1="socks5h://$base"
    local c2="socks5://$base"
    say "Testing proxy (1/2): $c1"
    if proxy_try "$c1"; then ok "Proxy OK. Using: $c1"; PROXY="$c1"; return; fi
    say "Testing proxy (2/2): $c2"
    if proxy_try "$c2"; then ok "Proxy OK. Using: $c2"; PROXY="$c2"; return; fi
    err "Proxy failed (both). Try again."
  done
}

# ============================================================
# TELEGRAM SEND (check ok:true)
# ============================================================
telegram_send(){
  local chat_id="$1"
  local caption="$2"
  local file="$3"
  local api="https://api.telegram.org/bot${TOKEN}/sendDocument"
  local response=""

  if [ -n "${PROXY:-}" ]; then
    response="$(curl -sS --proxy "$PROXY" \
      -F chat_id="$chat_id" \
      -F caption="$caption" \
      -F document=@"$file" \
      "$api" 2>&1 || true)"
  else
    response="$(curl -sS \
      -F chat_id="$chat_id" \
      -F caption="$caption" \
      -F document=@"$file" \
      "$api" 2>&1 || true)"
  fi

  if echo "$response" | grep -q '"ok"[[:space:]]*:[[:space:]]*true'; then
    ok "Telegram: sent successfully ✅"
    return 0
  fi

  err "Telegram send FAILED!"
  err "Response: $response"
  return 1
}

# ============================================================
# COMMANDS
# ============================================================
cmd_version(){ echo -e "${WHT}mbm${NC} ${YLW}v${VERSION}${NC}"; }

cmd_status(){
  title "MBM Status  v${VERSION}"

  [ -x "$MBM_BIN" ] && ok "Binary: $MBM_BIN" || warn "Binary: not installed"
  [ -f "$CONF" ] && ok "Config: $CONF" || warn "Config: missing (run mbm install)"

  if crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
    ok "Cron: active"
    crontab -l 2>/dev/null | grep "$CRON_TAG" || true
  else
    warn "Cron: not set"
  fi

  echo -e "${CYN}Backup dir:${NC} $BACKUP_DIR"
  local LAST=""
  LAST="$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -n1 || true)"
  if [ -n "$LAST" ]; then
    ok "Last backup: $LAST ($(du -sh "$LAST" 2>/dev/null | cut -f1))"
  else
    warn "Last backup: none"
  fi

  if [ -f "$CRON_LOG" ]; then
    echo -e "${CYN}Last cron log:${NC}"
    tail -n 5 "$CRON_LOG" || true
  fi

  if [ -f "$CONF" ]; then
    load_conf
    if [ -n "${PROXY:-}" ]; then
      echo -e "${CYN}Proxy:${NC} $PROXY"
      proxy_try "$PROXY" && ok "Proxy test: OK" || warn "Proxy test: FAIL"
    else
      echo -e "${CYN}Proxy:${NC} (none)"
    fi
    echo -e "${CYN}Max backups:${NC} ${MAX_BACKUPS:-}"
    echo -e "${CYN}Interval (min):${NC} ${INTERVAL_MINUTES:-}"
  fi

  MARZBAN_BIN="$(detect_marzban)"
  if [ -n "$MARZBAN_BIN" ]; then ok "marzban: $MARZBAN_BIN"; else warn "marzban: not found in PATH"; fi
}

cmd_update(){
  ensure_deps
  say "Updating mbm from GitHub..."
  local tmp
  tmp="$(mktemp)"

  curl -fsSL "$REMOTE_SCRIPT" -o "$tmp" || { err "Download failed: $REMOTE_SCRIPT"; rm -f "$tmp"; exit 1; }
  install -m 755 "$tmp" "$MBM_BIN"
  mkdir -p "$APP_DIR"
  echo "$VERSION" > "$APP_DIR/VERSION" || true
  rm -f "$tmp"
  ok "Updated. Current version: $($MBM_BIN version | tr -d '\r')"
}

cmd_install(){
  ensure_deps

  while true; do
    echo -e "${CYN}Telegram Bot Token:${NC}"
    read_tty TOKEN ""
    [[ "${TOKEN:-}" =~ ^[0-9]+:.{20,}$ ]] && break
    err "Invalid token format. Example: 123456789:ABCdef..."
  done

  while true; do
    echo -e "${CYN}Telegram Chat ID:${NC}"
    read_tty CHAT_ID ""
    [[ "${CHAT_ID:-}" =~ ^-?[0-9]+$ ]] && break
    err "Invalid Chat ID. Must be a number (e.g. -100123456789 or 123456789)"
  done

  validate_proxy

  while true; do
    echo -e "${CYN}Backup interval (minutes, >= 1):${NC}"
    read_tty INTERVAL_MINUTES ""
    [[ "${INTERVAL_MINUTES:-}" =~ ^[0-9]+$ ]] && [ "$INTERVAL_MINUTES" -ge 1 ] && break
    err "Please enter a valid number >= 1"
  done

  while true; do
    echo -e "${CYN}Max backups to keep (>= 1):${NC}"
    read_tty MAX_BACKUPS ""
    [[ "${MAX_BACKUPS:-}" =~ ^[0-9]+$ ]] && [ "$MAX_BACKUPS" -ge 1 ] && break
    err "Please enter a valid number >= 1"
  done

  save_conf
  setup_cron
  ok "Installed successfully ✅"
  say "Running first backup now..."
  cmd_backup
}

cmd_backup(){
ensure_deps
load_conf

[ -z "$MARZBAN_BIN" ] && { err "marzban command not found."; exit 1; }

local OUT_DIR="/opt/marzban-backup/backups"
mkdir -p "$OUT_DIR"

local STAMP HUMAN FINAL TMP
STAMP=$(jalali_stamp)
HUMAN=$(jalali_human)
FINAL="$OUT_DIR/backup_${STAMP}.tar.gz"
TMP="$(mktemp -p "$OUT_DIR" "backup_${STAMP}.XXXXXX.tar.gz")"

say "Creating full backup (path-preserving)..."
say "Includes: /opt/marzban  +  /var/lib/marzban"
warn "Excluding: /opt/marzban/backup  and  /var/lib/marzban/xray-core"

# Stop marzban briefly to avoid sqlite changing during tar
say "Stopping Marzban (safe snapshot)..."
"$MARZBAN_BIN" down >/dev/null 2>&1 || true

# Always try to start marzban back even if something fails
start_back(){
  say "Starting Marzban..."
  "$MARZBAN_BIN" restart -n >/dev/null 2>&1 || \
  "$MARZBAN_BIN" restart    >/dev/null 2>&1 || \
  "$MARZBAN_BIN" up -n      >/dev/null 2>&1 || \
  "$MARZBAN_BIN" up         >/dev/null 2>&1 || true
}
trap start_back EXIT

# Create archive (ignore harmless file-changed warnings if any)
set +e
tar -czf "$TMP" -C / \
  --exclude='opt/marzban/backup' \
  --exclude='opt/marzban/backup/*' \
  --exclude='var/lib/marzban/xray-core' \
  --exclude='var/lib/marzban/xray-core/*' \
  opt/marzban var/lib/marzban
rc=$?
set -e

if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
  rm -f "$TMP" >/dev/null 2>&1 || true
  err "Failed to create backup archive (tar exit: $rc)."
  exit 1
fi

mv -f "$TMP" "$FINAL"

local SIZE
SIZE=$(du -sh "$FINAL" 2>/dev/null | awk '{print $1}')
ok "Backup created: $FINAL (${SIZE:-?})"

local CAPTION
CAPTION="📦 Backup Information
🌐 Server IP: $(get_server_ip)
📁 Backup File: $FINAL
💾 Size: ${SIZE:-?}
⏰ Backup Time: $HUMAN"

say "Sending to Telegram..."
telegram_send "$CHAT_ID" "$CAPTION" "$FINAL" || {
  err "Backup file kept locally at: $FINAL"
  echo "$(date): FAILED to send $FINAL (${SIZE:-?})" >> "$APP_DIR/cron.log"
  exit 1
}

echo "$(date): OK — $FINAL (${SIZE:-?})" >> "$APP_DIR/cron.log"

# cleanup old backups
if [ -n "$MAX_BACKUPS" ] && [[ "$MAX_BACKUPS" =~ ^[0-9]+$ ]] && [ "$MAX_BACKUPS" -gt 0 ]; then
  local COUNT REMOVE
  COUNT=$(ls -1 "$OUT_DIR"/backup_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
  if [ "$COUNT" -gt "$MAX_BACKUPS" ]; then
    REMOVE=$(( COUNT - MAX_BACKUPS ))
    ls -1t "$OUT_DIR"/backup_*.tar.gz | tail -n "$REMOVE" | xargs -r rm -f
    say "Old backups cleaned. Keeping last $MAX_BACKUPS backups."
  fi
fi

ok "Backup completed and sent ✅"
}


cmd_restore(){
  ensure_deps
  load_conf

  MARZBAN_BIN="$(detect_marzban)"
  [ -z "$MARZBAN_BIN" ] && { err "marzban binary not found! Make sure marzban is installed."; exit 1; }

  local LATEST INPUT FILE CONFIRM
  LATEST="$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -n1 || true)"

  echo
  title "MBM Restore  v${VERSION}"

  if [ -z "$LATEST" ]; then
    err "No backups found in: $BACKUP_DIR"
    exit 1
  fi

  echo -e "${CYN}Latest backup found:${NC}"
  echo -e "  ${WHT}$LATEST${NC} ($(du -sh "$LATEST" 2>/dev/null | cut -f1 || echo "?"))"
  echo
  echo -e "${YLW}Enter backup file path to restore.${NC}"
  echo -e "${YLW}Press ENTER to restore latest:${NC} ${WHT}$LATEST${NC}"
  echo

  read_tty INPUT "Backup path: "
  FILE="${INPUT:-$LATEST}"

  [ -f "$FILE" ] || { err "Backup file not found: $FILE"; exit 1; }

  echo
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${RED}⚠⚠  WARNING — DANGEROUS OPERATION  ⚠⚠${NC}"
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${WHT}This will REPLACE your current Marzban data with:${NC}"
  echo -e "  ${YLW}$FILE${NC}"
  echo
  echo -e "${YLW}Type exactly:${NC} ${WHT}yes${NC}  ${YLW}to continue.${NC}"
  echo -e "${YLW}Press ENTER or anything else to cancel.${NC}"
  echo

  read_tty CONFIRM "Confirm (yes): "
  [ "${CONFIRM:-}" = "yes" ] || { warn "Restore cancelled."; exit 0; }

  say "Stopping Marzban..."
  "$MARZBAN_BIN" down >/dev/null 2>&1 || true

  say "Validating backup structure..."
  tar -tzf "$FILE" | grep -Eq '^(./)?opt/marzban/' || { err "Invalid backup: missing opt/marzban/"; exit 1; }
  tar -tzf "$FILE" | grep -Eq '^(./)?var/lib/marzban/' || { err "Invalid backup: missing var/lib/marzban/"; exit 1; }

  say "Restoring backup..."
  tar --touch -xzf "$FILE" -C / || { err "Restore failed while extracting archive."; exit 1; }

  say "Starting Marzban..."
  "$MARZBAN_BIN" restart -n >/dev/null 2>&1 || \
  "$MARZBAN_BIN" restart >/dev/null 2>&1 || \
  "$MARZBAN_BIN" up -n >/dev/null 2>&1 || \
  "$MARZBAN_BIN" up >/dev/null 2>&1 || true

  ok "Restore completed successfully ✅"
}

cmd_uninstall(){
  crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab - 2>/dev/null || true
  rm -rf "$APP_DIR"
  rm -f "$MBM_BIN"
  ok "Uninstalled ✅"
}

# ============================================================
# SELF-INSTALL
# ============================================================
self_install(){
  title "Installing Marzban Backup Manager v${VERSION}"
  say "Copying to: $MBM_BIN"
  install -m 755 "$SCRIPT_PATH" "$MBM_BIN"
  mkdir -p "$APP_DIR"
  echo "$VERSION" > "$APP_DIR/VERSION" || true
  ok "Installed at $MBM_BIN"
  echo
  "$MBM_BIN" install
}

# ============================================================
# ENTRY
# ============================================================
case "${1:-}" in
  install)   cmd_install ;;
  backup)    cmd_backup ;;
  restore)   cmd_restore ;;
  status)    cmd_status ;;
  version)   cmd_version ;;
  update)    cmd_update ;;
  uninstall) cmd_uninstall ;;
  help)      help ;;
  "")
    if [ "$(basename "$0")" = "install.sh" ]; then
      self_install
    else
      help
    fi
    ;;
  *) help ;;
esac
