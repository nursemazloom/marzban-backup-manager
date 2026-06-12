#!/usr/bin/env bash
# ============================================================
# Marzban Backup Manager (MBM)
# Single-file: installer + mbm binary
# Version: 1.2.0 (Added Bale, Rubika, Arvan, Toggles, Reinstall)
# ============================================================
set -e

VERSION="1.2.0"

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
  printf "  ${WHT}%-12s${NC} | %s\n" "install"   "Setup Telegram/Bale/Rubika/Arvan + Schedule"
  printf "  ${WHT}%-12s${NC} | %s\n" "reinstall" "Update configs and schedule without deleting old backups"
  printf "  ${WHT}%-12s${NC} | %s\n" "backup"    "Create backup now and send to enabled platforms"
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

  python3 -m pip install -q --upgrade pip >/dev/null 2>&1 || true
  
  # Install jdatetime
  python3 -c "import jdatetime" >/dev/null 2>&1 || {
    apt-get install -y python3-jdatetime >/dev/null 2>&1 || true
    python3 -m pip install -q jdatetime --break-system-packages >/dev/null 2>&1 || \
    python3 -m pip install -q --user jdatetime >/dev/null 2>&1 || true
  }
  
  # Install boto3 for ArvanCloud
  python3 -c "import boto3" >/dev/null 2>&1 || {
    python3 -m pip install -q boto3 --break-system-packages >/dev/null 2>&1 || \
    python3 -m pip install -q --user boto3 >/dev/null 2>&1 || true
  }

  python3 -c "import jdatetime" >/dev/null 2>&1 && ok "jdatetime is ready" || warn "jdatetime not installed"
  python3 -c "import boto3" >/dev/null 2>&1 && ok "boto3 is ready" || warn "boto3 not installed (Arvan might fail)"
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
  # shellcheck disable=SC1090
  source "$CONF"
  PANEL_TYPE="${PANEL_TYPE:-marzban}"
  PG_HAS_NODE="${PG_HAS_NODE:-false}"
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
    echo -e "${WHT}SOCKS5 Proxy (optional, mainly for Telegram)${NC}"
    echo "Formats:"
    echo "  socks5h://127.0.0.1:1080"
    echo "  socks5://127.0.0.1:1080"
    echo "  127.0.0.1:1080"
    echo "Leave empty if not needed, or press Enter to keep current: ${YLW}[${PROXY}]${NC}"
    read -r INPUT

    if [ -z "$INPUT" ]; then 
      INPUT="$PROXY"
      if [ -z "$INPUT" ]; then PROXY=""; return; fi
    fi
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
    err "Proxy failed (both). Try again or leave empty."
  done
}

# ============================================================
# PLATFORM UPLOADS
# ============================================================
telegram_send(){
  local chat_id="$1" caption="$2" file="$3"
  local api="https://api.telegram.org/bot${TOKEN}/sendDocument"
  local response

  if [ -n "${PROXY:-}" ]; then
    response="$(curl --proxy "$PROXY" -s -F chat_id="$chat_id" -F caption="$caption" -F document=@"$file" "$api" 2>&1 || true)"
  else
    response="$(curl -s -F chat_id="$chat_id" -F caption="$caption" -F document=@"$file" "$api" 2>&1 || true)"
  fi

  if echo "$response" | grep -q '"ok":true'; then
    ok "Telegram: sent successfully ✅"
    return 0
  fi
  err "Telegram send FAILED! Response: $response"
  return 1
}

bale_send(){
  local token="$1" chat_id="$2" caption="$3" file="$4"
  local api="https://tapi.bale.ai/bot${token}/sendDocument"
  local response
  # Bale usually doesn't need proxy for Iran servers
  response="$(curl -s -F chat_id="$chat_id" -F caption="$caption" -F document=@"$file" "$api" 2>&1 || true)"
  
  if echo "$response" | grep -q '"ok":true'; then
    ok "Bale: sent successfully ✅"
    return 0
  fi
  err "Bale send FAILED! Response: $response"
  return 1
}

rubika_send(){
  local token="$1" chat_id="$2" caption="$3" file="$4"
  # Placeholder for standard bot API. Rubika might need custom gateway URL.
  local api="https://messenger.rubika.ir/v3/bot${token}/sendDocument"
  local response
  
  response="$(curl -s -F chat_id="$chat_id" -F caption="$caption" -F document=@"$file" "$api" 2>&1 || true)"
  
  if echo "$response" | grep -q '"ok":true'; then
    ok "Rubika: sent successfully ✅"
    return 0
  fi
  err "Rubika send FAILED! Response: $response"
  # Don't strictly fail the script if Rubika fails, just log it.
  return 0 
}

arvan_upload_and_clean(){
  local file="$1" max="$2"
  say "Processing ArvanCloud (Upload & Clean in 'mbm/' folder)..."
  
  python3 - <<EOF
import os, sys, boto3
from botocore.client import Config

FILE_PATH = "$file"
MAX_BACKUPS = int("$max") if "$max".isdigit() else 5
ACCESS_KEY = "$ARVAN_ACCESS_KEY"
SECRET_KEY = "$ARVAN_SECRET_KEY"
ENDPOINT = "$ARVAN_ENDPOINT"
BUCKET = "$ARVAN_BUCKET"
PREFIX = "mbm/"

try:
    s3 = boto3.client(
        's3',
        endpoint_url=ENDPOINT,
        aws_access_key_id=ACCESS_KEY,
        aws_secret_access_key=SECRET_KEY,
        config=Config(signature_version='s3v4')
    )
    
    file_name = os.path.basename(FILE_PATH)
    object_name = f"{PREFIX}{file_name}"
    
    print(f"➜ Uploading {file_name} to ArvanCloud folder '{PREFIX}'...")
    s3.upload_file(FILE_PATH, BUCKET, object_name)
    print("✔ ArvanCloud: Upload successful ✅")
    
    # Cleanup Old Backups
    print(f"➜ Checking old backups in ArvanCloud folder '{PREFIX}' (Max: {MAX_BACKUPS})...")
    response = s3.list_objects_v2(Bucket=BUCKET, Prefix=PREFIX)
    if 'Contents' in response:
        objects = response['Contents']
        # فیلتر کردن خود پوشه در صورت وجود
        objects = [obj for obj in objects if obj['Key'] != PREFIX] 
        objects.sort(key=lambda x: x['LastModified'])
        
        while len(objects) > MAX_BACKUPS:
            oldest = objects[0]
            print(f"➜ Deleting old backup from Arvan: {oldest['Key']}")
            s3.delete_object(Bucket=BUCKET, Key=oldest['Key'])
            objects.pop(0)
        print("✔ ArvanCloud: Cleanup completed ✅")
    
except Exception as e:
    print(f"✖ ArvanCloud Error: {str(e)}")
    sys.exit(1)
EOF
}

# ============================================================
# HELPER FOR PROMPTS
# ============================================================
ask_yes_no() {
  local prompt="$1" var_name="$2" default="$3"
  local input
  while true; do
    echo -e "${CYN}${prompt} (y/n) [${default}]:${NC}"
    read -r input
    input="${input:-$default}"
    if [[ "$input" == "y" || "$input" == "Y" ]]; then eval "$var_name=\"true\""; return; fi
    if [[ "$input" == "n" || "$input" == "N" ]]; then eval "$var_name=\"false\""; return; fi
  done
}

ask_val() {
  local prompt="$1" var_name="$2" default="$3"
  local input
  echo -e "${CYN}${prompt} [${default}]:${NC}"
  read -r input
  input="${input:-$default}"
  eval "$var_name=\"$input\""
}

# ============================================================
# PANEL SELECTION
# ============================================================
ask_panel_type() {
  echo
  title "Panel Selection"
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
    ask_val "Arvan Endpoint (e.g. https://s3.ir-thr-at1.arvanstorage.ir):" "ARVAN_ENDPOINT" "$ARVAN_ENDPOINT"
    ask_val "Arvan Bucket Name:" "ARVAN_BUCKET" "$ARVAN_BUCKET"
  fi

  validate_proxy

  while true; do
    ask_val "Backup interval (minutes, >= 1):" "INTERVAL_MINUTES" "${INTERVAL_MINUTES:-360}"
    [[ "$INTERVAL_MINUTES" =~ ^[0-9]+$ ]] && [ "$INTERVAL_MINUTES" -ge 1 ] && break
    err "Please enter a valid number >= 1"
  done

  while true; do
    ask_val "Max backups to keep locally and on Arvan (>= 1):" "MAX_BACKUPS" "${MAX_BACKUPS:-5}"
    [[ "$MAX_BACKUPS" =~ ^[0-9]+$ ]] && [ "$MAX_BACKUPS" -ge 1 ] && break
    err "Please enter a valid number >= 1"
  done
}

# ============================================================
# VERSION & STATUS
# ============================================================
cmd_version(){ echo -e "${WHT}mbm${NC} ${YLW}v${VERSION}${NC}"; }

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
    echo -e "\n${CYN}Enabled Platforms:${NC}"
    [ "$ENABLE_TELEGRAM" = "true" ] && ok "Telegram"
    [ "$ENABLE_BALE" = "true" ] && ok "Bale"
    [ "$ENABLE_RUBIKA" = "true" ] && ok "Rubika"
    [ "$ENABLE_ARVAN" = "true" ] && ok "ArvanCloud"
    
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

  ok "Updated to $(/usr/local/bin/mbm version | tr -d '\n')"
}

# ============================================================
# INSTALL & REINSTALL
# ============================================================
cmd_install(){
  ensure_deps
  gather_config
  save_conf
  setup_cron
  ok "Installed successfully ✅"
  say "Running first backup now..."
  cmd_backup
}

cmd_reinstall(){
  say "Reinstalling / Updating Configs..."
  ensure_deps
  if [ -f "$CONF" ]; then
    load_conf
    say "Current config loaded. Press Enter to keep current values."
  fi
  gather_config
  save_conf
  setup_cron
  ok "Reinstalled successfully ✅"
}

# ============================================================
# BACKUP
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

  local TAR_ARGS=(--warning=no-file-changed)

  if [ "$PANEL_TYPE" = "pasarguard" ]; then
    say "Creating full backup for PasarGuard (path-preserving)..."
    say "Includes: /opt/pasarguard + /var/lib/pasarguard"
    [ -d /opt/pasarguard ] && TAR_ARGS+=(opt/pasarguard)
    [ -d /var/lib/pasarguard ] && TAR_ARGS+=(var/lib/pasarguard)
    if [ "$PG_HAS_NODE" = "true" ]; then
      say "Includes Node: /opt/pg-node + /var/lib/pg-node"
      [ -d /opt/pg-node ] && TAR_ARGS+=(opt/pg-node)
      [ -d /var/lib/pg-node ] && TAR_ARGS+=(var/lib/pg-node)
    fi
  else
    say "Creating full backup for Marzban (path-preserving)..."
    say "Includes: /opt/marzban  +  /var/lib/marzban"
    warn "Excluding: /opt/marzban/backup  and  /var/lib/marzban/xray-core"
    TAR_ARGS+=(--exclude='opt/marzban/backup' --exclude='opt/marzban/backup/*')
    TAR_ARGS+=(--exclude='var/lib/marzban/xray-core' --exclude='var/lib/marzban/xray-core/*')
    [ -d /opt/marzban ] && TAR_ARGS+=(opt/marzban)
    [ -d /var/lib/marzban ] && TAR_ARGS+=(var/lib/marzban)
  fi

  if [ ${#TAR_ARGS[@]} -eq 1 ]; then
      err "No valid directories found to backup for $PANEL_TYPE!"
      rm -f "$FINAL" || true
      exit 1
  fi

  set +e
  tar -czf "$FINAL" -C / "${TAR_ARGS[@]}"
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
⚙️ Panel: $PANEL_TYPE
📁 File: $(basename "$FINAL")
💾 Size: $SIZE
⏰ Time: $HUMAN"

  local ALL_OK="true"

  # Upload logic based on toggles
  if [ "$ENABLE_TELEGRAM" = "true" ]; then
    say "Sending to Telegram..."
    telegram_send "$CHAT_ID" "$CAPTION" "$FINAL" || ALL_OK="false"
  fi

  if [ "$ENABLE_BALE" = "true" ]; then
    say "Sending to Bale..."
    bale_send "$BALE_TOKEN" "$BALE_CHAT_ID" "$CAPTION" "$FINAL" || ALL_OK="false"
  fi

  if [ "$ENABLE_RUBIKA" = "true" ]; then
    say "Sending to Rubika..."
    rubika_send "$RUBIKA_TOKEN" "$RUBIKA_CHAT_ID" "$CAPTION" "$FINAL" || ALL_OK="false"
  fi

  if [ "$ENABLE_ARVAN" = "true" ]; then
    arvan_upload_and_clean "$FINAL" "$MAX_BACKUPS" || ALL_OK="false"
  fi

  # Log result
  if [ "$ALL_OK" = "true" ]; then
    echo "$(date): OK — $FINAL ($SIZE)" >> "$APP_DIR/cron.log"
  else
    err "One or more backup destinations failed."
    echo "$(date): WARNING/FAILED to send to some destinations — $FINAL ($SIZE)" >> "$APP_DIR/cron.log"
  fi

  # cleanup old backups LOCALLY
  if [ -n "${MAX_BACKUPS:-}" ] && [[ "$MAX_BACKUPS" =~ ^[0-9]+$ ]] && [ "$MAX_BACKUPS" -gt 0 ]; then
    local COUNT REMOVE
    COUNT="$(ls -1 "$OUT_DIR"/backup_*.tar.gz 2>/dev/null | wc -l)"
    if [ "$COUNT" -gt "$MAX_BACKUPS" ]; then
      REMOVE=$(( COUNT - MAX_BACKUPS ))
      ls -1t "$OUT_DIR"/backup_*.tar.gz | tail -n "$REMOVE" | xargs -r rm -f
      say "Old local backups cleaned. Keeping last $MAX_BACKUPS backups."
    fi
  fi

  ok "Backup process finished ✅"
}

# ============================================================
# RESTORE
# ============================================================
cmd_restore(){
  ensure_deps
  load_conf

  if [ "$PANEL_TYPE" = "marzban" ]; then
    [ -z "$MARZBAN_BIN" ] && { err "marzban binary not found! Make sure marzban is installed."; exit 1; }
  fi

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
  echo -e "${WHT}This will REPLACE your current data with:${NC}"
  echo -e "  ${YLW}$FILE${NC}"
  echo
  echo -e "${YLW}Type exactly:${NC} ${WHT}yes${NC}  ${YLW}to continue.${NC}"

  read -r -p "Confirm (yes): " CONFIRM
  [ "$CONFIRM" = "yes" ] || { warn "Restore cancelled."; exit 0; }

  say "Stopping Panel..."
  if [ "$PANEL_TYPE" = "marzban" ]; then
    "$MARZBAN_BIN" down >/dev/null 2>&1 || true
  fi

  say "Validating backup..."
  if [ "$PANEL_TYPE" = "pasarguard" ]; then
    tar -tzf "$FILE" | grep -Eq '^(./)?opt/pasarguard/' || { err "Invalid backup: missing opt/pasarguard/"; exit 1; }
  else
    tar -tzf "$FILE" | grep -Eq '^(./)?opt/marzban/' || { err "Invalid backup: missing opt/marzban/"; exit 1; }
    tar -tzf "$FILE" | grep -Eq '^(./)?var/lib/marzban/' || { err "Invalid backup: missing var/lib/marzban/"; exit 1; }
  fi

  say "Restoring backup..."
  tar --touch -xzf "$FILE" -C / || { err "Restore failed while extracting archive."; exit 1; }

  say "Starting Panel..."
  if [ "$PANEL_TYPE" = "pasarguard" ]; then
    say "Restore extracted. Please manually restart your PasarGuard containers/services if required."
  else
    "$MARZBAN_BIN" restart -n >/dev/null 2>&1 || \
    "$MARZBAN_BIN" restart >/dev/null 2>&1 || \
    "$MARZBAN_BIN" up -n >/dev/null 2>&1 || \
    "$MARZBAN_BIN" up >/dev/null 2>&1 || true
  fi

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
  say "Installing to /usr/local/bin/mbm ..."
  TMP_FILE="$(mktemp)"
  curl -fsSL "$REPO_RAW_BASE/install.sh" -o "$TMP_FILE" || { err "Download failed"; rm -f "$TMP_FILE"; exit 1; }
  install -m 755 "$TMP_FILE" /usr/local/bin/mbm
  rm -f "$TMP_FILE"
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
  reinstall) cmd_reinstall ;;
  backup)    cmd_backup ;;
  restore)   cmd_restore ;;
  status)    cmd_status ;;
  version)   cmd_version ;;
  update)    cmd_update ;;
  uninstall) cmd_uninstall ;;
  help)      help ;;
  "" )
if [ ! -x /usr/local/bin/mbm ]; then
  self_install
else
  help
fi
;;
  *) help ;;
esac
