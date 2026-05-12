#!/usr/bin/env bash
# ============================================================
# Marzban Backup Manager (MBM)
# Single-file: installer + mbm binary
# Version: 1.2.1
# Destinations: Telegram, Bale, Rubika, Arvan Object Storage
# ============================================================
set -e

VERSION="1.2.1"

# ===== Paths =====
APP_DIR="/opt/marzban-backup"
CONF="$APP_DIR/config.conf"
CRON_TAG="# mbm-backup"
REPO_RAW_BASE="https://raw.githubusercontent.com/nursemazloom/marzban-backup-manager/main"
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"

# ===== Colors =====
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; CYN='\033[0;36m'
MAG='\033[0;35m'; WHT='\033[1;37m'; NC='\033[0m'
say(){ echo -e "${CYN}➜${NC} $*"; }
ok(){ echo -e "${GRN}✔${NC} $*"; }
warn(){ echo -e "${YLW}⚠${NC} $*"; }
err(){ echo -e "${RED}✖${NC} $*"; }
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
  echo -e "${WHT}Marzban Backup Manager (mbm)${NC} ${YLW}v${VERSION}${NC}"
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYN}Usage:${NC} mbm <command>\n"
  echo -e "${YLW}Commands:${NC}"
  printf "  ${WHT}%-12s${NC} | %s\n" "install" "Setup destinations + proxy + schedule (runs first backup)"
  printf "  ${WHT}%-12s${NC} | %s\n" "reinstall" "Remove old config + cron, then run install again"
  printf "  ${WHT}%-12s${NC} | %s\n" "backup" "Create backup now and send/upload to enabled destinations"
  printf "  ${WHT}%-12s${NC} | %s\n" "restore" "Interactive restore (asks backup path and confirmation)"
  printf "  ${WHT}%-12s${NC} | %s\n" "status" "Show mbm + cron + destinations + last backup status"
  printf "  ${WHT}%-12s${NC} | %s\n" "version" "Show version"
  printf "  ${WHT}%-12s${NC} | %s\n" "update" "Update mbm from GitHub (keeps config)"
  printf "  ${WHT}%-12s${NC} | %s\n" "uninstall" "Remove mbm + cron + config"
  printf "  ${WHT}%-12s${NC} | %s\n" "help" "Show this help"
  echo
  echo -e "${YLW}Proxy formats (optional):${NC}"
  echo -e "  socks5h://127.0.0.1:1080  (recommended for Iran)"
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
  apt-get install -y curl cron python3 python3-pip tar gzip iproute2 ca-certificates openssl >/dev/null 2>&1 || true
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
  if [ "${ARVAN_ENABLED:-false}" = "true" ] && ! command -v python3 >/dev/null 2>&1; then install_deps; fi
}

# ============================================================
# CONFIG
# ============================================================
esc_conf(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
save_conf(){
  mkdir -p "$APP_DIR"
  cat > "$CONF" <<EOF_CONF
# MBM config v${VERSION}
# Destinations can be true/false
TELEGRAM_ENABLED="${TELEGRAM_ENABLED:-false}"
BALE_ENABLED="${BALE_ENABLED:-false}"
RUBIKA_ENABLED="${RUBIKA_ENABLED:-false}"
ARVAN_ENABLED="${ARVAN_ENABLED:-false}"

# Telegram
TOKEN="$(esc_conf "${TOKEN:-}")"
CHAT_ID="$(esc_conf "${CHAT_ID:-}")"

# Bale
BALE_TOKEN="$(esc_conf "${BALE_TOKEN:-}")"
BALE_CHAT_ID="$(esc_conf "${BALE_CHAT_ID:-}")"

# Rubika
RUBIKA_TOKEN="$(esc_conf "${RUBIKA_TOKEN:-}")"
RUBIKA_CHAT_ID="$(esc_conf "${RUBIKA_CHAT_ID:-}")"

# Arvan Object Storage (S3-compatible)
ARVAN_ENDPOINT="$(esc_conf "${ARVAN_ENDPOINT:-}")"
ARVAN_BUCKET="$(esc_conf "${ARVAN_BUCKET:-}")"
ARVAN_ACCESS_KEY="$(esc_conf "${ARVAN_ACCESS_KEY:-}")"
ARVAN_SECRET_KEY="$(esc_conf "${ARVAN_SECRET_KEY:-}")"
ARVAN_REGION="$(esc_conf "${ARVAN_REGION:-auto}")"
ARVAN_PATH="$(esc_conf "${ARVAN_PATH:-mbm}")"

# Common
PROXY="$(esc_conf "${PROXY:-}")"
INTERVAL_MINUTES="${INTERVAL_MINUTES:-1440}"
MAX_BACKUPS="${MAX_BACKUPS:-7}"
EOF_CONF
  chmod 600 "$CONF"
  ok "Config saved: $CONF"
}
load_conf(){
  [ -f "$CONF" ] || { err "Config not found. Run: mbm install"; exit 1; }
  # shellcheck disable=SC1090
  . "$CONF"
  TELEGRAM_ENABLED="${TELEGRAM_ENABLED:-true}"
  BALE_ENABLED="${BALE_ENABLED:-false}"
  RUBIKA_ENABLED="${RUBIKA_ENABLED:-false}"
  ARVAN_ENABLED="${ARVAN_ENABLED:-false}"
  ARVAN_REGION="${ARVAN_REGION:-auto}"
  ARVAN_PATH="${ARVAN_PATH:-mbm}"
}

ask_yes_no(){
  local prompt="$1" default="${2:-n}" ans
  while true; do
    if [ "$default" = "y" ]; then
      read -r -p "$prompt [Y/n]: " ans
      ans="${ans:-y}"
    else
      read -r -p "$prompt [y/N]: " ans
      ans="${ans:-n}"
    fi
    case "$ans" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) err "Please answer y or n" ;;
    esac
  done
}

# ============================================================
# CRON
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
remove_mbm_cron(){
  crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab - 2>/dev/null || true
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
proxy_curl_args(){
  [ -n "${PROXY:-}" ] && printf '%s\n' --proxy "$PROXY"
}
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
    if [[ "$INPUT" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
      base="$INPUT"
    elif [[ "$INPUT" =~ ^socks5h:// ]]; then
      base="${INPUT#socks5h://}"
    elif [[ "$INPUT" =~ ^socks5:// ]]; then
      base="${INPUT#socks5://}"
    else
      err "Invalid format."; continue
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
# DESTINATION SENDERS
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
  if echo "$response" | grep -q '"ok":true'; then ok "Telegram: sent successfully ✅"; return 0; fi
  err "Telegram send FAILED!"; err "Response: $response"; return 1
}

bale_send(){
  local chat_id="$1" caption="$2" file="$3"
  local api="https://tapi.bale.ai/bot${BALE_TOKEN}/sendDocument"
  local response
  if [ -n "${PROXY:-}" ]; then
    response="$(curl --proxy "$PROXY" -F chat_id="$chat_id" -F caption="$caption" -F document=@"$file" "$api" 2>&1 || true)"
  else
    response="$(curl -F chat_id="$chat_id" -F caption="$caption" -F document=@"$file" "$api" 2>&1 || true)"
  fi
  if echo "$response" | grep -q '"ok":true'; then ok "Bale: sent successfully ✅"; return 0; fi
  err "Bale send FAILED!"; err "Response: $response"; return 1
}

json_get(){
  local key="$1"
  python3 -c 'import json,sys; data=json.load(sys.stdin); key=sys.argv[1]; print(data.get(key) or data.get("data",{}).get(key) or data.get("file",{}).get(key) or "")' "$key" 2>/dev/null || true
}

rubika_send(){
  local chat_id="$1" caption="$2" file="$3"
  local base="https://botapi.rubika.ir/v3/${RUBIKA_TOKEN}"
  local req upload_url upload_resp file_id send_resp

  req="$(curl -sS --max-time 30 -X POST "$base/requestSendFile" \
    -H 'Content-Type: application/json' \
    --data '{"type":"File"}' 2>&1 || true)"
  upload_url="$(printf '%s' "$req" | json_get upload_url)"
  if [ -z "$upload_url" ]; then
    err "Rubika requestSendFile FAILED!"
    err "Response: $req"
    return 1
  fi

  upload_resp="$(curl -sS --max-time 300 -F file=@"$file" "$upload_url" 2>&1 || true)"
  file_id="$(printf '%s' "$upload_resp" | json_get file_id)"
  if [ -z "$file_id" ]; then
    err "Rubika file upload FAILED!"
    err "Response: $upload_resp"
    return 1
  fi

  send_resp="$(python3 - "$base/sendFile" "$chat_id" "$file_id" "$caption" <<'PY' 2>&1 || true
import json, sys, urllib.request
url, chat_id, file_id, text = sys.argv[1:5]
payload = json.dumps({"chat_id": chat_id, "file_id": file_id, "text": text}).encode()
req = urllib.request.Request(url, data=payload, headers={"Content-Type":"application/json"}, method="POST")
with urllib.request.urlopen(req, timeout=60) as r:
    print(r.read().decode())
PY
)"
  if echo "$send_resp" | grep -Eq '"message_id"|"status"[[:space:]]*:[[:space:]]*"OK"|"ok"[[:space:]]*:[[:space:]]*true'; then
    ok "Rubika: sent successfully ✅"
    return 0
  fi
  err "Rubika sendFile FAILED!"; err "Response: $send_resp"; return 1
}

arvan_upload(){
  local caption="$1" file="$2"
  local key path_prefix
  command -v python3 >/dev/null 2>&1 || { err "python3 not found"; return 1; }
  path_prefix="${ARVAN_PATH#/}"
  path_prefix="${path_prefix%/}"
  [ -n "$path_prefix" ] && key="$path_prefix/$(basename "$file")" || key="$(basename "$file")"

  ARVAN_ENDPOINT="$ARVAN_ENDPOINT" \
  ARVAN_BUCKET="$ARVAN_BUCKET" \
  ARVAN_ACCESS_KEY="$ARVAN_ACCESS_KEY" \
  ARVAN_SECRET_KEY="$ARVAN_SECRET_KEY" \
  ARVAN_REGION="${ARVAN_REGION:-auto}" \
  ARVAN_KEY="$key" \
  ARVAN_FILE="$file" \
  python3 - <<'PY_ARVAN' >/tmp/mbm_arvan.out 2>&1
import datetime, hashlib, hmac, mimetypes, os, urllib.error, urllib.parse, urllib.request

endpoint = os.environ.get("ARVAN_ENDPOINT", "").rstrip("/")
bucket = os.environ.get("ARVAN_BUCKET", "")
access_key = os.environ.get("ARVAN_ACCESS_KEY", "")
secret_key = os.environ.get("ARVAN_SECRET_KEY", "")
region = os.environ.get("ARVAN_REGION", "auto") or "auto"
key = os.environ.get("ARVAN_KEY", "")
file_path = os.environ.get("ARVAN_FILE", "")

if not all([endpoint, bucket, access_key, secret_key, key, file_path]):
    raise SystemExit("Missing Arvan Object Storage config")

parsed = urllib.parse.urlparse(endpoint)
if not parsed.scheme or not parsed.netloc:
    raise SystemExit("Invalid ARVAN_ENDPOINT. Example: https://s3.ir-thr-at1.arvanstorage.ir")

host = parsed.netloc
if region == "auto":
    parts = host.split(".")
    region = parts[1] if len(parts) > 2 and parts[0] == "s3" else "us-east-1"

with open(file_path, "rb") as f:
    body = f.read()

payload_hash = hashlib.sha256(body).hexdigest()
now = datetime.datetime.utcnow()
amz_date = now.strftime("%Y%m%dT%H%M%SZ")
date_stamp = now.strftime("%Y%m%d")
service = "s3"
method = "PUT"
encoded_key = "/".join(urllib.parse.quote(part, safe="") for part in key.split("/"))
canonical_uri = "/" + urllib.parse.quote(bucket, safe="") + "/" + encoded_key
canonical_querystring = ""
content_type = mimetypes.guess_type(file_path)[0] or "application/octet-stream"
canonical_headers = (
    f"content-type:{content_type}\n"
    f"host:{host}\n"
    f"x-amz-content-sha256:{payload_hash}\n"
    f"x-amz-date:{amz_date}\n"
)
signed_headers = "content-type;host;x-amz-content-sha256;x-amz-date"
canonical_request = "\n".join([method, canonical_uri, canonical_querystring, canonical_headers, signed_headers, payload_hash])
credential_scope = f"{date_stamp}/{region}/{service}/aws4_request"
string_to_sign = "\n".join(["AWS4-HMAC-SHA256", amz_date, credential_scope, hashlib.sha256(canonical_request.encode()).hexdigest()])

def sign(key_bytes, msg):
    return hmac.new(key_bytes, msg.encode(), hashlib.sha256).digest()

signing_key = sign(sign(sign(sign(("AWS4" + secret_key).encode(), date_stamp), region), service), "aws4_request")
signature = hmac.new(signing_key, string_to_sign.encode(), hashlib.sha256).hexdigest()
authorization = f"AWS4-HMAC-SHA256 Credential={access_key}/{credential_scope}, SignedHeaders={signed_headers}, Signature={signature}"
url = endpoint + canonical_uri
headers = {
    "Content-Type": content_type,
    "Host": host,
    "X-Amz-Content-Sha256": payload_hash,
    "X-Amz-Date": amz_date,
    "Authorization": authorization,
}
req = urllib.request.Request(url, data=body, headers=headers, method="PUT")
try:
    with urllib.request.urlopen(req, timeout=300) as r:
        print(f"HTTP {r.status} {r.reason}")
        print(f"s3://{bucket}/{key}")
except urllib.error.HTTPError as e:
    print(f"HTTP {e.code} {e.reason}")
    print(e.read().decode(errors="replace"))
    raise SystemExit(1)
PY_ARVAN
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "Arvan: uploaded to s3://$ARVAN_BUCKET/$key ✅"
    printf '%s\n%s\n' "$(date): $caption" "s3://$ARVAN_BUCKET/$key" >> "$APP_DIR/arvan.log" || true
    return 0
  fi
  err "Arvan upload FAILED!"
  err "Response: $(cat /tmp/mbm_arvan.out 2>/dev/null)"
  return 1
}
send_all_destinations(){
  local caption="$1" file="$2" failed=0 enabled=0

  if [ "${TELEGRAM_ENABLED:-false}" = "true" ]; then
    enabled=$((enabled+1)); say "Sending to Telegram..."; telegram_send "$CHAT_ID" "$caption" "$file" || failed=$((failed+1))
  fi
  if [ "${BALE_ENABLED:-false}" = "true" ]; then
    enabled=$((enabled+1)); say "Sending to Bale..."; bale_send "$BALE_CHAT_ID" "$caption" "$file" || failed=$((failed+1))
  fi
  if [ "${RUBIKA_ENABLED:-false}" = "true" ]; then
    enabled=$((enabled+1)); say "Sending to Rubika..."; rubika_send "$RUBIKA_CHAT_ID" "$caption" "$file" || failed=$((failed+1))
  fi
  if [ "${ARVAN_ENABLED:-false}" = "true" ]; then
    enabled=$((enabled+1)); say "Uploading to Arvan Object Storage..."; arvan_upload "$caption" "$file" || failed=$((failed+1))
  fi

  if [ "$enabled" -eq 0 ]; then err "No destination is enabled. Run: mbm reinstall"; return 1; fi
  if [ "$failed" -gt 0 ]; then err "$failed destination(s) failed. Backup file kept locally at: $file"; return 1; fi
  return 0
}

# ============================================================
# VERSION / STATUS / UPDATE
# ============================================================
cmd_version(){ echo -e "${WHT}mbm${NC} ${YLW}v${VERSION}${NC}"; }
cmd_status(){
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${WHT}MBM Status${NC} ${YLW}v${VERSION}${NC}"
  echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  [ -x /usr/local/bin/mbm ] && ok "Binary: /usr/local/bin/mbm" || err "Binary not found"
  [ -f "$CONF" ] && ok "Config: $CONF" || warn "Config: missing (run mbm install)"
  if crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
    ok "Cron: active"
    crontab -l 2>/dev/null | grep "$CRON_TAG" || true
  else
    warn "Cron: not set"
  fi
  local DIR="$APP_DIR/backups" LAST
  echo -e "${CYN}Backup dir:${NC} $DIR"
  LAST="$(ls -t "$DIR"/*.tar.gz 2>/dev/null | head -n1 || true)"
  if [ -n "$LAST" ]; then ok "Last backup: $LAST ($(du -sh "$LAST" 2>/dev/null | cut -f1))"; else warn "Last backup: none"; fi
  [ -f "$APP_DIR/cron.log" ] && { echo -e "${CYN}Last cron log:${NC}"; tail -n 5 "$APP_DIR/cron.log"; }
  if [ -f "$CONF" ]; then
    load_conf
    echo -e "${CYN}Destinations:${NC} Telegram=${TELEGRAM_ENABLED}, Bale=${BALE_ENABLED}, Rubika=${RUBIKA_ENABLED}, Arvan=${ARVAN_ENABLED}"
    if [ -n "${PROXY:-}" ]; then echo -e "${CYN}Proxy:${NC} $PROXY"; proxy_try "$PROXY" && ok "Proxy test: OK" || warn "Proxy test: FAIL"; else echo -e "${CYN}Proxy:${NC} (none)"; fi
  fi
  [ -n "$MARZBAN_BIN" ] && ok "marzban: $MARZBAN_BIN" || warn "marzban: not found in PATH"
}
cmd_update(){
  say "Updating mbm from GitHub..."
  local tmp
  tmp="$(mktemp)"
  curl -fsSL "$REPO_RAW_BASE/install.sh" -o "$tmp" || { err "Download failed"; rm -f "$tmp"; exit 1; }
  install -m 755 "$tmp" /usr/local/bin/mbm
  rm -f "$tmp"
  ok "Updated to $(/usr/local/bin/mbm version | tr -d ' ')"
}

# ============================================================
# INSTALL / REINSTALL
# ============================================================
cmd_install(){
  ensure_deps
  title "MBM install v${VERSION}"

  if ask_yes_no "Enable Telegram?" "y"; then
    TELEGRAM_ENABLED="true"
    while true; do echo -e "${CYN}Telegram Bot Token:${NC}"; read -r TOKEN; [[ "$TOKEN" =~ ^[0-9]+:.{20,}$ ]] && break; err "Invalid token format. Expected: 123456789:ABCdef..."; done
    while true; do echo -e "${CYN}Telegram Chat ID:${NC}"; read -r CHAT_ID; [[ "$CHAT_ID" =~ ^-?[0-9]+$ ]] && break; err "Invalid Chat ID. Must be a number."; done
  else
    TELEGRAM_ENABLED="false"; TOKEN=""; CHAT_ID=""
  fi

  if ask_yes_no "Enable Bale?" "n"; then
    BALE_ENABLED="true"
    echo -e "${CYN}Bale Bot Token:${NC}"; read -r BALE_TOKEN
    echo -e "${CYN}Bale Chat ID:${NC}"; read -r BALE_CHAT_ID
  else
    BALE_ENABLED="false"; BALE_TOKEN=""; BALE_CHAT_ID=""
  fi

  if ask_yes_no "Enable Rubika?" "n"; then
    RUBIKA_ENABLED="true"
    echo -e "${CYN}Rubika Bot Token:${NC}"; read -r RUBIKA_TOKEN
    echo -e "${CYN}Rubika Chat ID:${NC}"; read -r RUBIKA_CHAT_ID
  else
    RUBIKA_ENABLED="false"; RUBIKA_TOKEN=""; RUBIKA_CHAT_ID=""
  fi

  if ask_yes_no "Enable Arvan Object Storage?" "n"; then
    ARVAN_ENABLED="true"
    echo -e "${CYN}Arvan endpoint:${NC}"
    echo "Example: https://s3.ir-thr-at1.arvanstorage.ir"
    read -r ARVAN_ENDPOINT
    echo -e "${CYN}Arvan bucket name:${NC}"; read -r ARVAN_BUCKET
    echo -e "${CYN}Arvan access key:${NC}"; read -r ARVAN_ACCESS_KEY
    echo -e "${CYN}Arvan secret key:${NC}"; read -r ARVAN_SECRET_KEY
    echo -e "${CYN}Arvan region (default: auto, example: ir-thr-at1):${NC}"; read -r ARVAN_REGION; ARVAN_REGION="${ARVAN_REGION:-auto}"
    echo -e "${CYN}Path inside bucket (default: mbm):${NC}"; read -r ARVAN_PATH; ARVAN_PATH="${ARVAN_PATH:-mbm}"
  else
    ARVAN_ENABLED="false"; ARVAN_ENDPOINT=""; ARVAN_BUCKET=""; ARVAN_ACCESS_KEY=""; ARVAN_SECRET_KEY=""; ARVAN_REGION="auto"; ARVAN_PATH="mbm"
  fi

  if [ "$TELEGRAM_ENABLED" != "true" ] && [ "$BALE_ENABLED" != "true" ] && [ "$RUBIKA_ENABLED" != "true" ] && [ "$ARVAN_ENABLED" != "true" ]; then
    err "At least one destination must be enabled."
    exit 1
  fi

  validate_proxy
  while true; do echo -e "${CYN}Backup interval (minutes, >= 1):${NC}"; read -r INTERVAL_MINUTES; [[ "$INTERVAL_MINUTES" =~ ^[0-9]+$ ]] && [ "$INTERVAL_MINUTES" -ge 1 ] && break; err "Please enter a valid number >= 1"; done
  while true; do echo -e "${CYN}Max backups to keep (>= 1):${NC}"; read -r MAX_BACKUPS; [[ "$MAX_BACKUPS" =~ ^[0-9]+$ ]] && [ "$MAX_BACKUPS" -ge 1 ] && break; err "Please enter a valid number >= 1"; done

  save_conf
  setup_cron
  ok "Installed successfully ✅"
  say "Running first backup now..."
  cmd_backup
}
cmd_reinstall(){
  title "MBM reinstall v${VERSION}"
  warn "This will delete old MBM config and cron job, then start install again."
  read -r -p "Type exactly yes to continue: " CONFIRM
  [ "$CONFIRM" = "yes" ] || { warn "Reinstall cancelled."; exit 0; }
  remove_mbm_cron
  rm -f "$CONF" "$APP_DIR/cron.log" "$APP_DIR/arvan.log" "$APP_DIR/VERSION" 2>/dev/null || true
  ok "Old config and cron removed."
  cmd_install
}

# ============================================================
# BACKUP / RESTORE
# ============================================================
cmd_backup(){
  load_conf
  ensure_deps
  local OUT_DIR="$APP_DIR/backups"
  mkdir -p "$OUT_DIR"
  local STAMP HUMAN FINAL SIZE CAPTION
  STAMP="$(jalali_stamp)"
  HUMAN="$(jalali_human)"
  FINAL="$OUT_DIR/backup_${STAMP}.tar.gz"

  say "Creating full backup (path-preserving)..."
  say "Includes: /opt/marzban + /var/lib/marzban"
  warn "Excluding: /opt/marzban/backup and /var/lib/marzban/xray-core"

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

  SIZE="$(du -sh "$FINAL" 2>/dev/null | cut -f1)"
  ok "Backup created: $FINAL ($SIZE)"
  CAPTION="Backup Information
Server IP: $(get_server_ip)
File: $(basename "$FINAL")
Size: $SIZE
Time: $HUMAN"

  if ! send_all_destinations "$CAPTION" "$FINAL"; then
    echo "$(date): FAILED — $FINAL ($SIZE)" >> "$APP_DIR/cron.log"
    exit 1
  fi
  echo "$(date): OK — $FINAL ($SIZE)" >> "$APP_DIR/cron.log"

  if [ -n "${MAX_BACKUPS:-}" ] && [[ "$MAX_BACKUPS" =~ ^[0-9]+$ ]] && [ "$MAX_BACKUPS" -gt 0 ]; then
    local COUNT REMOVE
    COUNT="$(ls -1 "$OUT_DIR"/backup_*.tar.gz 2>/dev/null | wc -l)"
    if [ "$COUNT" -gt "$MAX_BACKUPS" ]; then
      REMOVE=$(( COUNT - MAX_BACKUPS ))
      ls -1t "$OUT_DIR"/backup_*.tar.gz | tail -n "$REMOVE" | xargs -r rm -f
      say "Old backups cleaned. Keeping last $MAX_BACKUPS backups."
    fi
  fi
  ok "Backup completed ✅"
}
cmd_restore(){
  ensure_deps
  load_conf
  [ -z "$MARZBAN_BIN" ] && { err "marzban binary not found! Make sure marzban is installed."; exit 1; }
  local BACKUP_DIR="$APP_DIR/backups" LATEST FILE INPUT CONFIRM
  LATEST="$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -n1 || true)"
  title "MBM Restore v${VERSION}"
  if [ -z "$LATEST" ]; then err "No backups found in: $BACKUP_DIR"; exit 1; fi
  echo -e "${CYN}Latest backup found:${NC}"
  echo -e "  ${WHT}$LATEST${NC} ($(du -sh "$LATEST" 2>/dev/null | cut -f1))"
  echo
  echo -e "${YLW}Enter backup file path to restore.${NC}"
  echo -e "${YLW}Press ENTER to restore latest:${NC} ${WHT}$LATEST${NC}"
  read -r -p "Backup path: " INPUT
  FILE="${INPUT:-$LATEST}"
  [ -f "$FILE" ] || { err "Backup file not found: $FILE"; exit 1; }
  echo
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${RED}⚠⚠ WARNING — DANGEROUS OPERATION ⚠⚠${NC}"
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${WHT}This will REPLACE your current Marzban data with:${NC}"
  echo -e "  ${YLW}$FILE${NC}"
  echo
  echo -e "${YLW}Type exactly:${NC} ${WHT}yes${NC} ${YLW}to continue.${NC}"
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
# UNINSTALL / SELF-INSTALL
# ============================================================
cmd_uninstall(){
  remove_mbm_cron
  rm -rf "$APP_DIR"
  rm -f /usr/local/bin/mbm
  ok "Uninstalled ✅"
}
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
  install) cmd_install ;;
  reinstall) cmd_reinstall ;;
  backup) cmd_backup ;;
  restore) cmd_restore ;;
  status) cmd_status ;;
  version) cmd_version ;;
  update) cmd_update ;;
  uninstall) cmd_uninstall ;;
  help) help ;;
  "" )
    if [ ! -x /usr/local/bin/mbm ]; then self_install; else help; fi
    ;;
  *) help ;;
esac
