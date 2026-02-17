#!/usr/bin/env bash
# ============================================================
# Marzban Backup Manager (MBM)
# Single-file: installer + mbm binary
# Version: 1.1.0
# ============================================================
set -e

VERSION="1.1.1"

# ===== Paths =====
APP_DIR="/opt/marzban-backup"
CONF="$APP_DIR/config.conf"
CRON_TAG="# mbm-backup"
REPO_RAW_BASE="https://raw.githubusercontent.com/nursemazloom/marzban-backup-manager/main"

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"

# ===== Colors =====
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; CYN='\033[0;36m'
MAG='\033[0;35m'; WHT='\033[1;37m'; NC='\033[0m'
say(){  echo -e "${CYN}➜${NC} $*"; }
ok(){   echo -e "${GRN}✔${NC} $*"; }
warn(){ echo -e "${YLW}⚠${NC} $*"; }
err(){  echo -e "${RED}✖${NC} $*"; }

title(){
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${WHT}$*${NC}"
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ===== marzban binary (robust) =====
MARZBAN_BIN="$(command -v marzban 2>/dev/null || true)"
[ -z "$MARZBAN_BIN" ] && [ -x /usr/local/bin/marzban ] && MARZBAN_BIN="/usr/local/bin/marzban"
[ -z "$MARZBAN_BIN" ] && [ -x /usr/bin/marzban ] && MARZBAN_BIN="/usr/bin/marzban"

# ============================================================
# HELP
# ============================================================
help(){
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${WHT}Marzban Backup Manager (mbm)${NC}  ${YLW}v${VERSION}${NC}"
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
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
  echo -e "  socks5h://127.0.0.1:1080   (recommended for Iran)"
  echo -e "  socks5://127.0.0.1:1080"
  echo -e "  or just: 127.0.0.1:1080"
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ============================================================
# SERVER IP
# ============================================================
get_server_ip() {
  local ip=""
  ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  [ -n "$ip" ] && { echo "$ip"; return 0; }
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
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

  python3 -c "import jdatetime" >/dev/null 2>&1 && { ok "jdatetime already available"; return; }

  apt-get install -y python3-jdatetime >/dev/null 2>&1 || true
  python3 -c "import jdatetime" >/dev/null 2>&1 && { ok "Installed jdatetime via apt"; return; }

  python3 -m pip install -q --upgrade pip >/dev/null 2>&1 || true
  python3 -m pip install -q jdatetime --break-system-packages >/dev/null 2>&1 || \
  python3 -m pip install -q --user jdatetime >/dev/null 2>&1 || true

  python3 -c "import jdatetime" >/dev/null 2>&1 && ok "Installed jdatetime via pip" || \
  warn "Could not auto-install jdatetime — Jalali timestamps may not work"
}

ensure_deps(){
  mkdir -p "$APP_DIR/backups"
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
  chmod 600 "$CONF"
}

load_conf(){
  [ -f "$CONF" ] || { err "Not installed. Run: mbm install"; exit 1; }
  # shellcheck disable=SC1090
  source "$CONF"
}

# ============================================================
# CRON  (>= 60 min => whole hours)
# ============================================================
cron_expr_from_minutes(){
  local M="$1"
  if ! [[ "$M" =~ ^[0-9]+$ ]] || [ "$M" -lt 1 ]; then echo ""; return; fi
  if [ "$M" -lt 60 ]; then echo "*/$M * * * *"; return; fi

  local H=$(( M / 60 ))
  local R=$(( M % 60 ))
  if [ "$R" -ne 0 ]; then
    warn "Interval $M min is not a multiple of 60. Rounding to ${H}h ($((H*60)) min)."
  fi
  if [ "$H" -lt 1 ]; then H=1; fi

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
  ( crontab -l 2>/dev/null; echo "$expr /usr/local/bin/mbm backup >>$APP_DIR/cron.log 2>&1 $CRON_TAG" ) | crontab -
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
    read -r INPUT

    if [ -z "$INPUT" ]; then PROXY=""; return; fi
    if [[ "$INPUT" =~ ^http ]]; then err "Invalid format (only socks5/socks5h)"; continue; fi

    local base=""
    if   [[ "$INPUT" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then base="$INPUT"
    elif [[ "$INPUT" =~ ^socks5h:// ]]; then base="${INPUT#socks5h://}"
    elif [[ "$INPUT" =~ ^socks5:// ]]; then base="${INPUT#socks5://}"
    else err "Invalid format."; continue
    fi

    local c1="socks5h://$base" c2="socks5://$base"
    say "Testing proxy (1/2): $c1"
    if proxy_try "$c1"; then ok "Proxy OK. Using: $c1"; PROXY="$c1"; return; fi
    say "Testing proxy (2/2): $c2"
    if proxy_try "$c2"; then ok "Proxy OK. Using: $c2"; PROXY="$c2"; return; fi
    err "Proxy failed (both). Try again."
  done
}

# ============================================================
# TELEGRAM SEND  (checks ok:true)
# ============================================================
telegram_send(){
  local chat_id="$1" caption="$2" file="$3"
  local api="https://api.telegram.org/bot${TOKEN}/sendDocument"
  local response

  if [ -n "${PROXY:-}" ]; then
    response="$(curl --proxy "$PROXY" -F chat_id="$chat_id" -F caption="$caption" -F document=@"$file" "$api" 2>&1 || true)"
  else
    response="$(curl -F chat_id="$chat_id" -F caption="$caption" -F document=@"$file" "$api" 2>&1 || true)"
  fi

  if echo "$response" | grep -q '"ok":true'; then
    ok "Telegram: sent successfully ✅"
    return 0
  fi
  err "Telegram send FAILED!"
  err "Response: $response"
  return 1
}

# ============================================================
# VERSION
# ============================================================
cmd_version(){ echo -e "${WHT}mbm${NC} ${YLW}v${VERSION}${NC}"; }

# ============================================================
# STATUS
# ============================================================
cmd_status(){
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${WHT}MBM Status${NC}  ${YLW}v${VERSION}${NC}"
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  [ -x /usr/local/bin/mbm ] && ok "Binary: /usr/local/bin/mbm" || err "Binary not found"
  [ -f "$CONF" ] && ok "Config: $CONF" || warn "Config: missing (run mbm install)"

  if crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
    ok "Cron: active"
    crontab -l 2>/dev/null | grep "$CRON_TAG" || true
  else
    warn "Cron: not set"
  fi

  local DIR="$APP_DIR/backups"
  echo -e "${CYN}Backup dir:${NC} $DIR"
  local LAST
  LAST="$(ls -t "$DIR"/*.tar.gz 2>/dev/null | head -n1 || true)"
  if [ -n "$LAST" ]; then
    ok "Last backup: $LAST ($(du -sh "$LAST" 2>/dev/null | cut -f1))"
  else
    warn "Last backup: none"
  fi

  [ -f "$APP_DIR/cron.log" ] && {
    echo -e "${CYN}Last cron log:${NC}"
    tail -n 5 "$APP_DIR/cron.log"
  }

  if [ -f "$CONF" ]; then
    load_conf
    if [ -n "${PROXY:-}" ]; then
      echo -e "${CYN}Proxy:${NC} $PROXY"
      proxy_try "$PROXY" && ok "Proxy test: OK" || warn "Proxy test: FAIL"
    else
      echo -e "${CYN}Proxy:${NC} (none)"
    fi
  fi

  [ -n "$MARZBAN_BIN" ] && ok "marzban: $MARZBAN_BIN" || warn "marzban: not found in PATH"
}

# ============================================================
# UPDATE (single-file)
# ============================================================
cmd_update(){
  say "Updating mbm from GitHub..."
  local tmp
  tmp="$(mktemp)"

  curl -fsSL "$REPO_RAW_BASE/install.sh" -o "$tmp" \
    || { err "Download failed"; rm -f "$tmp"; exit 1; }

  install -m 755 "$tmp" /usr/local/bin/mbm
  rm -f "$tmp"

  ok "Updated to $(/usr/local/bin/mbm version | tr -d '')"
}


# ============================================================
# INSTALL
# ============================================================
cmd_install(){
  ensure_deps

  while true; do
    echo -e "${CYN}Telegram Bot Token:${NC}"
    read -r TOKEN
    [[ "$TOKEN" =~ ^[0-9]+:.{35,}$ ]] && break
    err "Invalid token format. Expected: 123456789:ABCdef..."
  done

  while true; do
    echo -e "${CYN}Telegram Chat ID:${NC}"
    read -r CHAT_ID
    [[ "$CHAT_ID" =~ ^-?[0-9]+$ ]] && break
    err "Invalid Chat ID. Must be a number (e.g. -100123456789 or 123456789)"
  done

  validate_proxy

  while true; do
    echo -e "${CYN}Backup interval (minutes, >= 1):${NC}"
    read -r INTERVAL_MINUTES
    [[ "$INTERVAL_MINUTES" =~ ^[0-9]+$ ]] && [ "$INTERVAL_MINUTES" -ge 1 ] && break
    err "Please enter a valid number >= 1"
  done

  while true; do
    echo -e "${CYN}Max backups to keep (>= 1):${NC}"
    read -r MAX_BACKUPS
    [[ "$MAX_BACKUPS" =~ ^[0-9]+$ ]] && [ "$MAX_BACKUPS" -ge 1 ] && break
    err "Please enter a valid number >= 1"
  done

  save_conf
  setup_cron
  ok "Installed successfully ✅"
  say "Running first backup now..."
  cmd_backup
}

# ============================================================
# BACKUP  (NO stop/start, tolerate "file changed" warnings)
# ============================================================
cmd_backup(){
  ensure_deps
  load_conf

  local OUT_DIR="$APP_DIR/backups"
  mkdir -p "$OUT_DIR"

  local STAMP HUMAN FINAL
  STAMP="$(jalali_stamp)"
  HUMAN="$(jalali_human)"
  FINAL="$OUT_DIR/backup_${STAMP}.tar.gz"

  say "Creating full backup (path-preserving)..."
  say "Includes: /opt/marzban  +  /var/lib/marzban"
  warn "Excluding: /opt/marzban/backup  and  /var/lib/marzban/xray-core"

  # tar may warn "file changed as we read it" (exit code 1). We accept it if archive created.
  set +e
  tar -czf "$FINAL" -C / \
    --warning=no-file-changed \
    --exclude='opt/marzban/backup' \
    --exclude='opt/marzban/backup/*' \
    --exclude='var/lib/marzban/xray-core' \
    --exclude='var/lib/marzban/xray-core/*' \
    opt/marzban var/lib/marzban
  local rc=$?
  set -e

  if [ "$rc" -ne 0 ]; then
    if [ "$rc" -eq 1 ] && [ -s "$FINAL" ]; then
      warn "tar returned warnings (rc=1) but archive was created. Continuing..."
    else
      err "Failed to create backup archive (tar exit: $rc)."
      rm -f "$FINAL" || true
      exit 1
    fi
  fi

  local SIZE
  SIZE="$(du -sh "$FINAL" 2>/dev/null | cut -f1)"
  ok "Backup created: $FINAL ($SIZE)"

  local CAPTION
  CAPTION="📦 Backup Information
🌐 Server IP: $(get_server_ip)
📁 File: $(basename "$FINAL")
💾 Size: $SIZE
⏰ Time: $HUMAN"

  say "Sending to Telegram..."
  if ! telegram_send "$CHAT_ID" "$CAPTION" "$FINAL"; then
    err "Backup file kept locally at: $FINAL"
    echo "$(date): FAILED to send $FINAL ($SIZE)" >> "$APP_DIR/cron.log"
    exit 1
  fi

  echo "$(date): OK — $FINAL ($SIZE)" >> "$APP_DIR/cron.log"

  # cleanup old backups
  if [ -n "${MAX_BACKUPS:-}" ] && [[ "$MAX_BACKUPS" =~ ^[0-9]+$ ]] && [ "$MAX_BACKUPS" -gt 0 ]; then
    local COUNT REMOVE
    COUNT="$(ls -1 "$OUT_DIR"/backup_*.tar.gz 2>/dev/null | wc -l)"
    if [ "$COUNT" -gt "$MAX_BACKUPS" ]; then
      REMOVE=$(( COUNT - MAX_BACKUPS ))
      ls -1t "$OUT_DIR"/backup_*.tar.gz | tail -n "$REMOVE" | xargs -r rm -f
      say "Old backups cleaned. Keeping last $MAX_BACKUPS backups."
    fi
  fi

  ok "Backup completed and sent ✅"
}

# ============================================================
# RESTORE
# ============================================================
cmd_restore(){
  ensure_deps
  load_conf

  [ -z "$MARZBAN_BIN" ] && { err "marzban binary not found! Make sure marzban is installed."; exit 1; }

  local BACKUP_DIR="$APP_DIR/backups"
  local LATEST FILE INPUT CONFIRM
  LATEST="$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -n1 || true)"

  echo
  title "MBM Restore  v${VERSION}"

  if [ -z "$LATEST" ]; then
    err "No backups found in: $BACKUP_DIR"
    exit 1
  fi

  echo -e "${CYN}Latest backup found:${NC}"
  echo -e "  ${WHT}$LATEST${NC} ($(du -sh "$LATEST" 2>/dev/null | cut -f1))"
  echo
  echo -e "${YLW}Enter backup file path to restore.${NC}"
  echo -e "${YLW}Press ENTER to restore latest:${NC} ${WHT}$LATEST${NC}"
  echo

  read -r -p "Backup path: " INPUT
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

  read -r -p "Confirm (yes): " CONFIRM
  [ "$CONFIRM" = "yes" ] || { warn "Restore cancelled."; exit 0; }

  say "Stopping Marzban..."
  "$MARZBAN_BIN" down >/dev/null 2>&1 || true

  say "Validating backup..."
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

# ============================================================
# UNINSTALL
# ============================================================
cmd_uninstall(){
  crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab - 2>/dev/null || true
  rm -rf "$APP_DIR"
  rm -f /usr/local/bin/mbm
  ok "Uninstalled ✅"
}

# ============================================================
# SELF-INSTALL (when executed as install.sh)
# ============================================================
self_install(){
  title "Installing Marzban Backup Manager v${VERSION}"
  say "Copying mbm to /usr/local/bin/mbm ..."
  install -m 755 "$SCRIPT_PATH" /usr/local/bin/mbm
  mkdir -p "$APP_DIR"
  echo "$VERSION" > "$APP_DIR/VERSION" || true
  ok "Binary installed at /usr/local/bin/mbm"
  echo
  /usr/local/bin/mbm install
}

# ============================================================
# ENTRY POINT
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
    if [[ "$(basename "$0")" == "install.sh" ]]; then
      self_install
    else
      help
    fi
    ;;
  *) help ;;
esac
