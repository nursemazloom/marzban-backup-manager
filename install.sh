#!/usr/bin/env bash
# ============================================================
# Backup Manager (MBM) - Modified for Marzban & PasarGuard
# Single-file: installer + mbm binary
# ============================================================
set -e

VERSION="1.3.0-multi"

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

# ===== Binary Check (Dynamic based on panel) =====
get_panel_bin() {
    if [ "$PANEL_TYPE" = "pasarguard" ]; then
        # PasarGuard might not have a global binary like marzban, handling gracefully
        echo ""
    else
        local bin="$(command -v marzban 2>/dev/null || true)"
        [ -z "$bin" ] && [ -x /usr/local/bin/marzban ] && bin="/usr/local/bin/marzban"
        [ -z "$bin" ] && [ -x /usr/bin/marzban ] && bin="/usr/bin/marzban"
        echo "$bin"
    fi
}

# ============================================================
# HELP
# ============================================================
help(){
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${WHT}Backup Manager (mbm)${NC}  ${YLW}v${VERSION}${NC}"
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYN}Usage:${NC}  mbm <command>\n"
  echo -e "${YLW}Commands:${NC}"
  printf "  ${WHT}%-12s${NC} | %s\n" "install"   "Setup Panel Type, Platforms + Schedule"
  printf "  ${WHT}%-12s${NC} | %s\n" "reinstall" "Update configs without deleting old backups"
  printf "  ${WHT}%-12s${NC} | %s\n" "backup"    "Create backup now"
  printf "  ${WHT}%-12s${NC} | %s\n" "restore"   "Interactive restore"
  printf "  ${WHT}%-12s${NC} | %s\n" "status"    "Show status"
  printf "  ${WHT}%-12s${NC} | %s\n" "uninstall" "Remove mbm + cron + config"
  printf "  ${WHT}%-12s${NC} | %s\n" "help"      "Show this help"
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

get_server_ip() {
  local ip=""
  ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  [ -n "$ip" ] && { echo "$ip"; return 0; }
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [ -n "$ip" ] && { echo "$ip"; return 0; }
  ip="$(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
  echo "${ip:-unknown}"
}

install_deps(){
  say "Installing dependencies..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y curl cron python3 python3-pip tar gzip iproute2 ca-certificates >/dev/null 2>&1 || true
  systemctl enable --now cron >/dev/null 2>&1 || true

  python3 -m pip install -q --upgrade pip >/dev/null 2>&1 || true
  python3 -c "import jdatetime" >/dev/null 2>&1 || {
    apt-get install -y python3-jdatetime >/dev/null 2>&1 || true
    python3 -m pip install -q jdatetime --break-system-packages >/dev/null 2>&1 || \
    python3 -m pip install -q --user jdatetime >/dev/null 2>&1 || true
  }
  python3 -c "import boto3" >/dev/null 2>&1 || {
    python3 -m pip install -q boto3 --break-system-packages >/dev/null 2>&1 || \
    python3 -m pip install -q --user boto3 >/dev/null 2>&1 || true
  }
}

ensure_deps(){
  mkdir -p "$APP_DIR/backups"
  command -v curl >/dev/null 2>&1 || install_deps
  command -v python3 >/dev/null 2>&1 || install_deps
  command -v tar >/dev/null 2>&1 || install_deps
  python3 -c "import jdatetime" >/dev/null 2>&1 || install_deps
  python3 -c "import boto3" >/dev/null 2>&1 || install_deps
}

# ============================================================
# CONFIG
# ============================================================
save_conf(){
  mkdir -p "$APP_DIR"
  cat > "$CONF" <<CFG
PANEL_TYPE="$PANEL_TYPE"
PG_HAS_NODE="$PG_HAS_NODE"

ENABLE_TELEGRAM="$ENABLE_TELEGRAM"
TOKEN="$TOKEN"
CHAT_ID="$CHAT_ID"

ENABLE_BALE="$ENABLE_BALE"
BALE_TOKEN="$BALE_TOKEN"
BALE_CHAT_ID="$BALE_CHAT_ID"

ENABLE_RUBIKA="$ENABLE_RUBIKA"
RUBIKA_TOKEN="$RUBIKA_TOKEN"
RUBIKA_CHAT_ID="$RUBIKA_CHAT_ID"

ENABLE_ARVAN="$ENABLE_ARVAN"
ARVAN_ACCESS_KEY="$ARVAN_ACCESS_KEY"
ARVAN_SECRET_KEY="$ARVAN_SECRET_KEY"
ARVAN_ENDPOINT="$ARVAN_ENDPOINT"
ARVAN_BUCKET="$ARVAN_BUCKET"

PROXY="$PROXY"
INTERVAL_MINUTES="$INTERVAL_MINUTES"
MAX_BACKUPS="$MAX_BACKUPS"
CFG
  chmod 600 "$CONF"
}

load_conf(){
  [ -f "$CONF" ] || { err "Not installed. Run: mbm install"; exit 1; }
  source "$CONF"
  # Default to marzban if missing for backward compatibility
  PANEL_TYPE="${PANEL_TYPE:-marzban}" 
  PG_HAS_NODE="${PG_HAS_NODE:-false}"
}

cron_expr_from_minutes(){
  local M="$1"
  if ! [[ "$M" =~ ^[0-9]+$ ]] || [ "$M" -lt 1 ]; then echo ""; return; fi
  if [ "$M" -lt 60 ]; then echo "*/$M * * * *"; return; fi
  local H=$(( M / 60 ))
  local R=$(( M % 60 ))
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
  local expr="$(cron_expr_from_minutes "$INTERVAL_MINUTES")"
  [ -n "$expr" ] || { err "Invalid interval."; exit 1; }
  crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab - 2>/dev/null || true
  ( crontab -l 2>/dev/null; echo "$expr /usr/local/bin/mbm backup >>$APP_DIR/cron.log 2>&1 $CRON_TAG" ) | crontab -
  ok "Cron set: $expr"
}

jalali_stamp(){ python3 -c 'from datetime import datetime; import jdatetime; print(jdatetime.datetime.fromgregorian(datetime=datetime.now()).strftime("%Y-%m-%d_%H-%M-%S"))'; }
jalali_human(){ python3 -c 'from datetime import datetime; import jdatetime; print(jdatetime.datetime.fromgregorian(datetime=datetime.now()).strftime("%Y-%m-%d %H:%M:%S"))'; }

proxy_try(){ curl --proxy "$1" -I -s --max-time 10 https://api.telegram.org >/dev/null 2>&1; }

validate_proxy(){
  while true; do
    echo -e "\n${WHT}SOCKS5 Proxy (optional)${NC}"
    echo "Leave empty if not needed: ${YLW}[${PROXY}]${NC}"
    read -r INPUT
    if [ -z "$INPUT" ]; then 
      INPUT="$PROXY"
      if [ -z "$INPUT" ]; then PROXY=""; return; fi
    fi
    local base="${INPUT#*://}"
    local c1="socks5h://$base"
    if proxy_try "$c1"; then ok "Proxy OK."; PROXY="$c1"; return; fi
    err "Proxy failed."
  done
}

telegram_send(){
  local chat_id="$1" caption="$2" file="$3" api="https://api.telegram.org/bot${TOKEN}/sendDocument"
  local response
  if [ -n "${PROXY:-}" ]; then response="$(curl --proxy "$PROXY" -s -F chat_id="$chat_id" -F caption="$caption" -F document=@"$file" "$api" 2>&1 || true)"
  else response="$(curl -s -F chat_id="$chat_id" -F caption="$caption" -F document=@"$file" "$api" 2>&1 || true)"
  fi
  if echo "$response" | grep -q '"ok":true'; then ok "Telegram: sent ✅"; return 0; fi
  err "Telegram FAILED!"; return 1
}

bale_send(){
  local response="$(curl -s -F chat_id="$2" -F caption="$3" -F document=@"$4" "https://tapi.bale.ai/bot$1/sendDocument" 2>&1 || true)"
  if echo "$response" | grep -q '"ok":true'; then ok "Bale: sent ✅"; return 0; fi
  return 1
}

rubika_send(){
  local response="$(curl -s -F chat_id="$2" -F caption="$3" -F document=@"$4" "https://messenger.rubika.ir/v3/bot$1/sendDocument" 2>&1 || true)"
  if echo "$response" | grep -q '"ok":true'; then ok "Rubika: sent ✅"; return 0; fi
  return 0 
}

arvan_upload_and_clean(){
  python3 -c "
import os, sys, boto3
from botocore.client import Config
try:
    s3 = boto3.client('s3', endpoint_url='$ARVAN_ENDPOINT', aws_access_key_id='$ARVAN_ACCESS_KEY', aws_secret_access_key='$ARVAN_SECRET_KEY', config=Config(signature_version='s3v4'))
    file_name = os.path.basename('$1')
    object_name = f'mbm/{file_name}'
    s3.upload_file('$1', '$ARVAN_BUCKET', object_name)
    print('✔ ArvanCloud: Upload OK')
    resp = s3.list_objects_v2(Bucket='$ARVAN_BUCKET', Prefix='mbm/')
    if 'Contents' in resp:
        objs = [o for o in resp['Contents'] if o['Key'] != 'mbm/']
        objs.sort(key=lambda x: x['LastModified'])
        while len(objs) > int('${2:-5}'):
            s3.delete_object(Bucket='$ARVAN_BUCKET', Key=objs[0]['Key'])
            objs.pop(0)
except Exception as e:
    print(f'✖ Arvan Error: {str(e)}')
    sys.exit(1)
"
}

ask_yes_no() {
  local input
  while true; do
    echo -e "${CYN}$1 (y/n) [$3]:${NC}"
    read -r input
    input="${input:-$3}"
    if [[ "$input" == "y" || "$input" == "Y" ]]; then eval "$2=\"true\""; return; fi
    if [[ "$input" == "n" || "$input" == "N" ]]; then eval "$2=\"false\""; return; fi
  done
}

ask_val() {
  local input
  echo -e "${CYN}$1 [$3]:${NC}"
  read -r input
  input="${input:-$3}"
  eval "$2=\"$input\""
}

# ============================================================
# PANEL SELECTION
# ============================================================
ask_panel_type() {
  echo
  title "Panel Selection / انتخاب پنل"
  echo -e "${CYN}Koodom panel ro mikhayd backup begirid? (1 ya 2 ro vared konid)${NC}"
  echo "1) Marzban"
  echo "2) PasarGuard"
  
  local panel_choice
  while true; do
    read -r -p "Entekhab [1]: " panel_choice
    panel_choice="${panel_choice:-1}"
    if [ "$panel_choice" = "1" ]; then
      PANEL_TYPE="marzban"
      PG_HAS_NODE="false"
      break
    elif [ "$panel_choice" = "2" ]; then
      PANEL_TYPE="pasarguard"
      ask_yes_no "Aya Node PasarGuard ham rooye in server nasbe? (y/n)" "PG_HAS_NODE" "n"
      break
    else
      err "Lotfan 1 ya 2 ro vared konid."
    fi
  done
}

gather_config() {
  ask_panel_type
  
  echo
  title "Platform Configurations"
  
  ask_yes_no "Enable Telegram Backup?" "ENABLE_TELEGRAM" "${ENABLE_TELEGRAM:-true}"
  if [ "$ENABLE_TELEGRAM" = "true" ]; then
    ask_val "Telegram Bot Token:" "TOKEN" "$TOKEN"
    ask_val "Telegram Chat ID:" "CHAT_ID" "$CHAT_ID"
  fi

  ask_yes_no "Enable Bale Backup?" "ENABLE_BALE" "${ENABLE_BALE:-false}"
  if [ "$ENABLE_BALE" = "true" ]; then
    ask_val "Bale Bot Token:" "BALE_TOKEN" "$BALE_TOKEN"
    ask_val "Bale Chat ID:" "BALE_CHAT_ID" "$BALE_CHAT_ID"
  fi

  ask_yes_no "Enable Rubika Backup?" "ENABLE_RUBIKA" "${ENABLE_RUBIKA:-false}"
  if [ "$ENABLE_RUBIKA" = "true" ]; then
    ask_val "Rubika Bot Token:" "RUBIKA_TOKEN" "$RUBIKA_TOKEN"
    ask_val "Rubika Chat ID:" "RUBIKA_CHAT_ID" "$RUBIKA_CHAT_ID"
  fi

  ask_yes_no "Enable ArvanCloud Storage Backup?" "ENABLE_ARVAN" "${ENABLE_ARVAN:-false}"
  if [ "$ENABLE_ARVAN" = "true" ]; then
    ask_val "Arvan Access Key:" "ARVAN_ACCESS_KEY" "$ARVAN_ACCESS_KEY"
    ask_val "Arvan Secret Key:" "ARVAN_SECRET_KEY" "$ARVAN_SECRET_KEY"
    ask_val "Arvan Endpoint:" "ARVAN_ENDPOINT" "$ARVAN_ENDPOINT"
    ask_val "Arvan Bucket Name:" "ARVAN_BUCKET" "$ARVAN_BUCKET"
  fi

  validate_proxy

  while true; do
    ask_val "Backup interval (minutes, >= 1):" "INTERVAL_MINUTES" "${INTERVAL_MINUTES:-360}"
    [[ "$INTERVAL_MINUTES" =~ ^[0-9]+$ ]] && [ "$INTERVAL_MINUTES" -ge 1 ] && break
    err "Invalid number"
  done

  while true; do
    ask_val "Max backups to keep (>= 1):" "MAX_BACKUPS" "${MAX_BACKUPS:-5}"
    [[ "$MAX_BACKUPS" =~ ^[0-9]+$ ]] && [ "$MAX_BACKUPS" -ge 1 ] && break
    err "Invalid number"
  done
}

cmd_status(){
  load_conf
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${WHT}MBM Status${NC}  ${YLW}v${VERSION}${NC}"
  echo -e "${CYN}Panel Type:${NC} $PANEL_TYPE $([ "$PG_HAS_NODE" = "true" ] && echo "(+ Node)")"
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  
  local BIN="$(get_panel_bin)"
  [ -n "$BIN" ] && ok "Binary: $BIN" || warn "Panel binary not explicitly managed"

  local DIR="$APP_DIR/backups"
  local LAST="$(ls -t "$DIR"/*.tar.gz 2>/dev/null | head -n1 || true)"
  if [ -n "$LAST" ]; then ok "Last backup: $LAST"; else warn "Last backup: none"; fi
}

cmd_install(){
  ensure_deps
  gather_config
  save_conf
  setup_cron
  ok "Installed successfully ✅"
  cmd_backup
}

cmd_reinstall(){
  ensure_deps
  if [ -f "$CONF" ]; then load_conf; fi
  gather_config
  save_conf
  setup_cron
  ok "Reinstalled successfully ✅"
}

# ============================================================
# BACKUP LOGIC (DYNAMIC PATHS)
# ============================================================
cmd_backup(){
  ensure_deps
  load_conf

  local OUT_DIR="$APP_DIR/backups"
  mkdir -p "$OUT_DIR"
  local STAMP="$(jalali_stamp)"
  local FINAL="$OUT_DIR/backup_${PANEL_TYPE}_${STAMP}.tar.gz"

  local TAR_ARGS=()
  TAR_ARGS+=(--warning=no-file-changed)

  if [ "$PANEL_TYPE" = "marzban" ]; then
      say "Creating backup for Marzban..."
      TAR_ARGS+=(--exclude='opt/marzban/backup' --exclude='opt/marzban/backup/*')
      TAR_ARGS+=(--exclude='var/lib/marzban/xray-core' --exclude='var/lib/marzban/xray-core/*')
      
      # Use a workaround for paths that might not exist to prevent tar from failing entirely
      [ -d /opt/marzban ] && TAR_ARGS+=(opt/marzban)
      [ -d /var/lib/marzban ] && TAR_ARGS+=(var/lib/marzban)

  elif [ "$PANEL_TYPE" = "pasarguard" ]; then
      say "Creating backup for PasarGuard..."
      
      [ -d /opt/pasarguard ] && TAR_ARGS+=(opt/pasarguard)
      [ -d /var/lib/pasarguard ] && TAR_ARGS+=(var/lib/pasarguard)
      
      if [ "$PG_HAS_NODE" = "true" ]; then
          say "Including PasarGuard Node files..."
          [ -d /opt/pg-node ] && TAR_ARGS+=(opt/pg-node)
          [ -d /var/lib/pg-node ] && TAR_ARGS+=(var/lib/pg-node)
      fi
  fi

  if [ ${#TAR_ARGS[@]} -eq 1 ]; then
      err "No valid directories found to backup for $PANEL_TYPE!"
      exit 1
  fi

  set +e
  tar -czf "$FINAL" -C / "${TAR_ARGS[@]}"
  local rc=$?
  set -e

  if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
      err "Failed to create backup (tar exit: $rc)."
      rm -f "$FINAL" || true
      exit 1
  fi

  local SIZE="$(du -sh "$FINAL" 2>/dev/null | cut -f1)"
  ok "Backup created: $FINAL ($SIZE)"

  local CAPTION="📦 Backup Information
🌐 Server IP: $(get_server_ip)
⚙️ Panel: $PANEL_TYPE
📁 File: $(basename "$FINAL")
💾 Size: $SIZE
⏰ Time: $(jalali_human)"

  [ "$ENABLE_TELEGRAM" = "true" ] && telegram_send "$CHAT_ID" "$CAPTION" "$FINAL"
  [ "$ENABLE_BALE" = "true" ] && bale_send "$BALE_TOKEN" "$BALE_CHAT_ID" "$CAPTION" "$FINAL"
  [ "$ENABLE_RUBIKA" = "true" ] && rubika_send "$RUBIKA_TOKEN" "$RUBIKA_CHAT_ID" "$CAPTION" "$FINAL"
  [ "$ENABLE_ARVAN" = "true" ] && arvan_upload_and_clean "$FINAL" "$MAX_BACKUPS"

  if [ -n "${MAX_BACKUPS:-}" ] && [ "$MAX_BACKUPS" -gt 0 ]; then
    local COUNT="$(ls -1 "$OUT_DIR"/backup_*.tar.gz 2>/dev/null | wc -l)"
    if [ "$COUNT" -gt "$MAX_BACKUPS" ]; then
      ls -1t "$OUT_DIR"/backup_*.tar.gz | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm -f
    fi
  fi
  ok "Process finished ✅"
}

# ============================================================
# RESTORE LOGIC (DYNAMIC PATHS)
# ============================================================
cmd_restore(){
  ensure_deps
  load_conf

  local BACKUP_DIR="$APP_DIR/backups"
  local LATEST="$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -n1 || true)"
  [ -z "$LATEST" ] && { err "No backups found!"; exit 1; }

  echo -e "\n${YLW}Latest backup: $LATEST${NC}"
  read -r -p "Backup path [ENTER for latest]: " FILE
  FILE="${FILE:-$LATEST}"
  [ -f "$FILE" ] || { err "File not found."; exit 1; }

  read -r -p "Type 'yes' to OVERWRITE data with $FILE: " CONFIRM
  [ "$CONFIRM" = "yes" ] || { warn "Cancelled."; exit 0; }

  local BIN="$(get_panel_bin)"
  if [ -n "$BIN" ]; then
      say "Stopping panel..."
      "$BIN" down >/dev/null 2>&1 || true
  fi

  say "Restoring..."
  tar --touch -xzf "$FILE" -C / || { err "Extract failed."; exit 1; }

  if [ -n "$BIN" ]; then
      say "Starting panel..."
      "$BIN" restart >/dev/null 2>&1 || "$BIN" up -d >/dev/null 2>&1 || true
  else
      say "Please restart your panel manually if needed."
  fi
  ok "Restore complete ✅"
}

cmd_uninstall(){
  crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab - 2>/dev/null || true
  rm -rf "$APP_DIR" /usr/local/bin/mbm
  ok "Uninstalled ✅"
}

self_install(){
  title "Installing Backup Manager v${VERSION}"
  say "Installing to /usr/local/bin/mbm ..."
  TMP_FILE="$(mktemp)"
  curl -fsSL "$REPO_RAW_BASE/install.sh" -o "$TMP_FILE" || { err "Download failed"; rm -f "$TMP_FILE"; exit 1; }
  install -m 755 "$TMP_FILE" /usr/local/bin/mbm
  rm -f "$TMP_FILE"
  mkdir -p "$APP_DIR"
  ok "Binary installed at /usr/local/bin/mbm"
  echo
  /usr/local/bin/mbm install
}


case "${1:-}" in
  install)   cmd_install ;;
  reinstall) cmd_reinstall ;;
  backup)    cmd_backup ;;
  restore)   cmd_restore ;;
  status)    cmd_status ;;
  uninstall) cmd_uninstall ;;
  *) if [ ! -x /usr/local/bin/mbm ]; then self_install; else help; fi ;;
esac
