#!/usr/bin/env bash
set -euo pipefail

VERSION="1.2.4"

APP_DIR="/opt/marzban-backup"
BACKUP_DIR="$APP_DIR/backups"
CONFIG_FILE="$APP_DIR/config.conf"
BIN_PATH="/usr/local/bin/mbm"

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
CYN='\033[0;36m'
NC='\033[0m'

say(){ echo -e "${CYN}➜ $*${NC}"; }
ok(){ echo -e "${GRN}✔ $*${NC}"; }
warn(){ echo -e "${YLW}⚠ $*${NC}"; }
err(){ echo -e "${RED}✖ $*${NC}"; }

mkdir -p "$APP_DIR" "$BACKUP_DIR"

load_config() {
  [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
}

save_config() {
cat > "$CONFIG_FILE" <<EOF
TELEGRAM_ENABLED="$TELEGRAM_ENABLED"
BALE_ENABLED="$BALE_ENABLED"
RUBIKA_ENABLED="$RUBIKA_ENABLED"
ARVAN_ENABLED="$ARVAN_ENABLED"

TELEGRAM_TOKEN="$TELEGRAM_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"

BALE_TOKEN="$BALE_TOKEN"
BALE_CHAT_ID="$BALE_CHAT_ID"

RUBIKA_TOKEN="$RUBIKA_TOKEN"
RUBIKA_CHAT_ID="$RUBIKA_CHAT_ID"

ARVAN_ENDPOINT="$ARVAN_ENDPOINT"
ARVAN_BUCKET="$ARVAN_BUCKET"
ARVAN_ACCESS_KEY="$ARVAN_ACCESS_KEY"
ARVAN_SECRET_KEY="$ARVAN_SECRET_KEY"
ARVAN_REGION="$ARVAN_REGION"
ARVAN_PATH="$ARVAN_PATH"

MAX_BACKUPS="$MAX_BACKUPS"
CRON_SCHEDULE="$CRON_SCHEDULE"
EOF
ok "Config saved: $CONFIG_FILE"
}

telegram_send() {
  local caption="$1"
  local file="$2"

  RESPONSE=$(curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
    -F chat_id="$TELEGRAM_CHAT_ID" \
    -F caption="$caption" \
    -F document=@"$file")

  if echo "$RESPONSE" | grep -q '"ok":true'; then
    ok "Telegram: sent successfully ✅"
  else
    err "Telegram send FAILED!"
    err "Response: $RESPONSE"
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi
}

bale_send() {
  local caption="$1"
  local file="$2"

  RESPONSE=$(curl -s -X POST \
    "https://tapi.bale.ai/bot${BALE_TOKEN}/sendDocument" \
    -F chat_id="$BALE_CHAT_ID" \
    -F caption="$caption" \
    -F document=@"$file")

  if echo "$RESPONSE" | grep -q '"ok":true'; then
    ok "Bale: sent successfully ✅"
  else
    err "Bale send FAILED!"
    err "Response: $RESPONSE"
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi
}

rubika_send() {
  local file="$1"

  RESPONSE=$(curl -s -X POST \
    "https://messengerg2c56.iranlms.ir/" \
    -F token="$RUBIKA_TOKEN" \
    -F chat_id="$RUBIKA_CHAT_ID" \
    -F file=@"$file")

  if echo "$RESPONSE" | grep -q '"ok":true'; then
    ok "Rubika: sent successfully ✅"
  else
    err "Rubika file upload FAILED!"
    err "Response: $RESPONSE"
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi
}

arvan_upload() {
  local file="$1"
  local filename
  filename=$(basename "$file")

  local key="${ARVAN_PATH}/${filename}"

PYTHONWARNINGS=ignore python3 <<PY
import requests
from datetime import datetime
import hashlib, hmac

access_key = "$ARVAN_ACCESS_KEY"
secret_key = "$ARVAN_SECRET_KEY"
bucket = "$ARVAN_BUCKET"
endpoint = "$ARVAN_ENDPOINT".replace("https://","").replace("http://","")
region = "$ARVAN_REGION" or "auto"
service = "s3"
key = "$key"
file_path = "$file"
host = endpoint

t = datetime.utcnow()
amzdate = t.strftime('%Y%m%dT%H%M%SZ')
datestamp = t.strftime('%Y%m%d')

with open(file_path, "rb") as f:
    payload = f.read()

payload_hash = hashlib.sha256(payload).hexdigest()
canonical_uri = f"/{bucket}/{key}"

canonical_headers = (
    f"host:{host}\\n"
    f"x-amz-content-sha256:{payload_hash}\\n"
    f"x-amz-date:{amzdate}\\n"
)

signed_headers = "host;x-amz-content-sha256;x-amz-date"

canonical_request = (
    "PUT\\n" +
    canonical_uri + "\\n\\n" +
    canonical_headers + "\\n" +
    signed_headers + "\\n" +
    payload_hash
)

algorithm = "AWS4-HMAC-SHA256"
credential_scope = f"{datestamp}/{region}/{service}/aws4_request"

string_to_sign = (
    algorithm + "\\n" +
    amzdate + "\\n" +
    credential_scope + "\\n" +
    hashlib.sha256(canonical_request.encode()).hexdigest()
)

def sign(key, msg):
    return hmac.new(key, msg.encode(), hashlib.sha256).digest()

kDate = sign(("AWS4" + secret_key).encode(), datestamp)
kRegion = sign(kDate, region)
kService = sign(kRegion, service)
kSigning = sign(kService, "aws4_request")

signature = hmac.new(kSigning, string_to_sign.encode(), hashlib.sha256).hexdigest()

authorization_header = (
    f"{algorithm} "
    f"Credential={access_key}/{credential_scope}, "
    f"SignedHeaders={signed_headers}, "
    f"Signature={signature}"
)

url = f"https://{host}/{bucket}/{key}"

headers = {
    "x-amz-content-sha256": payload_hash,
    "x-amz-date": amzdate,
    "Authorization": authorization_header
}

r = requests.put(url, headers=headers, data=payload)
print(r.status_code)

if r.status_code not in (200, 201):
    print(r.text)
    raise SystemExit(1)
PY

  ok "Arvan: uploaded to s3://$ARVAN_BUCKET/$key ✅"

  arvan_cleanup
}

arvan_cleanup() {
  if [ -z "${MAX_BACKUPS:-}" ] || ! [[ "$MAX_BACKUPS" =~ ^[0-9]+$ ]] || [ "$MAX_BACKUPS" -le 0 ]; then
    return 0
  fi

  LIST=$(PYTHONWARNINGS=ignore python3 <<PY
import requests
from datetime import datetime
import hashlib, hmac

access_key = "$ARVAN_ACCESS_KEY"
secret_key = "$ARVAN_SECRET_KEY"
bucket = "$ARVAN_BUCKET"
endpoint = "$ARVAN_ENDPOINT".replace("https://","").replace("http://","")
region = "$ARVAN_REGION" or "auto"
service = "s3"
host = endpoint

t = datetime.utcnow()
amzdate = t.strftime('%Y%m%dT%H%M%SZ')
datestamp = t.strftime('%Y%m%d')

payload_hash = hashlib.sha256(b'').hexdigest()
canonical_uri = f"/{bucket}"
canonical_querystring = "list-type=2"

canonical_headers = (
    f"host:{host}\\n"
    f"x-amz-content-sha256:{payload_hash}\\n"
    f"x-amz-date:{amzdate}\\n"
)

signed_headers = "host;x-amz-content-sha256;x-amz-date"

canonical_request = (
    "GET\\n" +
    canonical_uri + "\\n" +
    canonical_querystring + "\\n" +
    canonical_headers + "\\n" +
    signed_headers + "\\n" +
    payload_hash
)

algorithm = "AWS4-HMAC-SHA256"
credential_scope = f"{datestamp}/{region}/{service}/aws4_request"

string_to_sign = (
    algorithm + "\\n" +
    amzdate + "\\n" +
    credential_scope + "\\n" +
    hashlib.sha256(canonical_request.encode()).hexdigest()
)

def sign(key, msg):
    return hmac.new(key, msg.encode(), hashlib.sha256).digest()

kDate = sign(("AWS4" + secret_key).encode(), datestamp)
kRegion = sign(kDate, region)
kService = sign(kRegion, service)
kSigning = sign(kService, "aws4_request")

signature = hmac.new(kSigning, string_to_sign.encode(), hashlib.sha256).hexdigest()

authorization_header = (
    f"{algorithm} "
    f"Credential={access_key}/{credential_scope}, "
    f"SignedHeaders={signed_headers}, "
    f"Signature={signature}"
)

url = f"https://{host}/{bucket}?{canonical_querystring}"

headers = {
    "x-amz-content-sha256": payload_hash,
    "x-amz-date": amzdate,
    "Authorization": authorization_header
}

r = requests.get(url, headers=headers)
print(r.text)
PY
)

  KEYS=$(echo "$LIST" | grep -oP '(?<=<Key>).*?(?=</Key>)' | grep "^${ARVAN_PATH}/backup_" | sort || true)
  COUNT=$(echo "$KEYS" | grep -c . || true)

  if [ "$COUNT" -le "$MAX_BACKUPS" ]; then
    return 0
  fi

  REMOVE=$((COUNT - MAX_BACKUPS))

  echo "$KEYS" | head -n "$REMOVE" | while read -r OLDKEY; do
    [ -z "$OLDKEY" ] && continue

PYTHONWARNINGS=ignore python3 <<PY
import requests
from datetime import datetime
import hashlib, hmac

access_key = "$ARVAN_ACCESS_KEY"
secret_key = "$ARVAN_SECRET_KEY"
bucket = "$ARVAN_BUCKET"
endpoint = "$ARVAN_ENDPOINT".replace("https://","").replace("http://","")
region = "$ARVAN_REGION" or "auto"
service = "s3"
key = "$OLDKEY"
host = endpoint

t = datetime.utcnow()
amzdate = t.strftime('%Y%m%dT%H%M%SZ')
datestamp = t.strftime('%Y%m%d')

payload_hash = hashlib.sha256(b'').hexdigest()
canonical_uri = f"/{bucket}/{key}"

canonical_headers = (
    f"host:{host}\\n"
    f"x-amz-content-sha256:{payload_hash}\\n"
    f"x-amz-date:{amzdate}\\n"
)

signed_headers = "host;x-amz-content-sha256;x-amz-date"

canonical_request = (
    "DELETE\\n" +
    canonical_uri + "\\n\\n" +
    canonical_headers + "\\n" +
    signed_headers + "\\n" +
    payload_hash
)

algorithm = "AWS4-HMAC-SHA256"
credential_scope = f"{datestamp}/{region}/{service}/aws4_request"

string_to_sign = (
    algorithm + "\\n" +
    amzdate + "\\n" +
    credential_scope + "\\n" +
    hashlib.sha256(canonical_request.encode()).hexdigest()
)

def sign(key, msg):
    return hmac.new(key, msg.encode(), hashlib.sha256).digest()

kDate = sign(("AWS4" + secret_key).encode(), datestamp)
kRegion = sign(kDate, region)
kService = sign(kRegion, service)
kSigning = sign(kService, "aws4_request")

signature = hmac.new(kSigning, string_to_sign.encode(), hashlib.sha256).hexdigest()

authorization_header = (
    f"{algorithm} "
    f"Credential={access_key}/{credential_scope}, "
    f"SignedHeaders={signed_headers}, "
    f"Signature={signature}"
)

url = f"https://{host}/{bucket}/{key}"

headers = {
    "x-amz-content-sha256": payload_hash,
    "x-amz-date": amzdate,
    "Authorization": authorization_header
}

r = requests.delete(url, headers=headers)

if r.status_code not in (200, 202, 204):
    print(f"DELETE_FAILED {r.status_code} {r.text}")
    raise SystemExit(1)
PY

    say "Deleted old Arvan backup: $OLDKEY"
  done

  ok "Arvan cleanup: kept=$MAX_BACKUPS deleted=$REMOVE"
}

cmd_backup() {
  load_config
  FAIL_COUNT=0

  DATE=$(date +%Y-%m-%d_%H-%M-%S)
  FILE="$BACKUP_DIR/backup_${DATE}.tar.gz"

  say "Creating full backup (path-preserving)..."
  say "Includes: /opt/marzban + /var/lib/marzban"

  tar \
    --exclude='/opt/marzban-backup/backups' \
    --exclude='/opt/marzban/backup' \
    --exclude='/var/lib/marzban/xray-core' \
    --exclude='*.log' \
    --exclude='*.log.*' \
    -czf "$FILE" \
    /opt/marzban /var/lib/marzban

  SIZE=$(du -h "$FILE" | awk '{print $1}')
  ok "Backup created: $FILE ($SIZE)"

  CAPTION="MBM Backup - $DATE"

  if [ "${TELEGRAM_ENABLED:-false}" = "true" ]; then
    say "Sending to Telegram..."
    telegram_send "$CAPTION" "$FILE"
  fi

  if [ "${BALE_ENABLED:-false}" = "true" ]; then
    say "Sending to Bale..."
    bale_send "$CAPTION" "$FILE"
  fi

  if [ "${RUBIKA_ENABLED:-false}" = "true" ]; then
    say "Sending to Rubika..."
    rubika_send "$FILE"
  fi

  if [ "${ARVAN_ENABLED:-false}" = "true" ]; then
    say "Uploading to Arvan Object Storage..."
    arvan_upload "$FILE"
  fi

  if [ "$FAIL_COUNT" -eq 0 ]; then
    ok "All destinations completed successfully ✅"
  else
    err "$FAIL_COUNT destination(s) failed. Backup file kept locally at: $FILE"
  fi

  if [ -n "${MAX_BACKUPS:-}" ] && [[ "$MAX_BACKUPS" =~ ^[0-9]+$ ]] && [ "$MAX_BACKUPS" -gt 0 ]; then
    COUNT=$(ls -1 "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | wc -l)

    if [ "$COUNT" -gt "$MAX_BACKUPS" ]; then
      REMOVE=$((COUNT - MAX_BACKUPS))
      ls -1t "$BACKUP_DIR"/backup_*.tar.gz | tail -n "$REMOVE" | xargs rm -f
      say "Old backups cleaned. Keeping last $MAX_BACKUPS backups."
    fi
  fi
}

cmd_install() {
  cp "$0" "$BIN_PATH"
  chmod +x "$BIN_PATH"

  TELEGRAM_ENABLED=false
  BALE_ENABLED=false
  RUBIKA_ENABLED=false
  ARVAN_ENABLED=false

  TELEGRAM_TOKEN=""
  TELEGRAM_CHAT_ID=""
  BALE_TOKEN=""
  BALE_CHAT_ID=""
  RUBIKA_TOKEN=""
  RUBIKA_CHAT_ID=""

  ARVAN_ENDPOINT=""
  ARVAN_BUCKET=""
  ARVAN_ACCESS_KEY=""
  ARVAN_SECRET_KEY=""
  ARVAN_REGION="auto"
  ARVAN_PATH="MBM"

  echo

  read -rp "Enable Telegram? (y/n): " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    TELEGRAM_ENABLED=true
    read -rp "Telegram Bot Token: " TELEGRAM_TOKEN
    read -rp "Telegram Chat ID: " TELEGRAM_CHAT_ID
  fi

  read -rp "Enable Bale? (y/n): " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    BALE_ENABLED=true
    read -rp "Bale Bot Token: " BALE_TOKEN
    read -rp "Bale Chat ID: " BALE_CHAT_ID
  fi

  read -rp "Enable Rubika? (y/n): " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    RUBIKA_ENABLED=true
    read -rp "Rubika Bot Token: " RUBIKA_TOKEN
    read -rp "Rubika Chat ID/GUID: " RUBIKA_CHAT_ID
  fi

  read -rp "Enable Arvan Object Storage? (y/n): " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    ARVAN_ENABLED=true
    read -rp "Arvan Endpoint: " ARVAN_ENDPOINT
    read -rp "Bucket Name: " ARVAN_BUCKET
    read -rp "Access Key: " ARVAN_ACCESS_KEY
    read -rp "Secret Key: " ARVAN_SECRET_KEY
    read -rp "Region [auto]: " ARVAN_REGION
    ARVAN_REGION="${ARVAN_REGION:-auto}"
    read -rp "Path Prefix [MBM]: " ARVAN_PATH
    ARVAN_PATH="${ARVAN_PATH:-MBM}"
  fi

  read -rp "Max backups to keep [7]: " MAX_BACKUPS
  MAX_BACKUPS="${MAX_BACKUPS:-7}"

  read -rp "Cron schedule [0 */1 * * *]: " CRON_SCHEDULE
  CRON_SCHEDULE="${CRON_SCHEDULE:-0 */1 * * *}"

  save_config

  (
    crontab -l 2>/dev/null | grep -v "$BIN_PATH backup" || true
    echo "$CRON_SCHEDULE $BIN_PATH backup >/dev/null 2>&1"
  ) | crontab -

  ok "Cron set: $CRON_SCHEDULE"
  ok "Installed successfully ✅"

  say "Running first backup now..."
  cmd_backup
}

cmd_reinstall() {
  say "Removing old config and cron jobs..."

  rm -f "$CONFIG_FILE"

  crontab -l 2>/dev/null | grep -v "$BIN_PATH backup" | crontab - || true

  ok "Old config removed."
  cmd_install
}

cmd_update() {
  curl -fsSL \
    https://raw.githubusercontent.com/nursemazloom/marzban-backup-manager/main/install.sh \
    -o "$BIN_PATH"

  chmod +x "$BIN_PATH"

  ok "Updated successfully to latest version ✅"
}

cmd_status() {
  load_config

  echo "MBM v$VERSION"
  echo
  echo "Config: $CONFIG_FILE"
  echo "Backup dir: $BACKUP_DIR"
  echo
  echo "Telegram: ${TELEGRAM_ENABLED:-false}"
  echo "Bale: ${BALE_ENABLED:-false}"
  echo "Rubika: ${RUBIKA_ENABLED:-false}"
  echo "Arvan: ${ARVAN_ENABLED:-false}"
  echo "Max backups: ${MAX_BACKUPS:-7}"
}

cmd_uninstall() {
  say "Removing MBM..."

  crontab -l 2>/dev/null | grep -v "$BIN_PATH backup" | crontab - || true

  rm -f "$BIN_PATH"

  ok "Uninstalled. Config and backups are kept at: $APP_DIR"
}

case "${1:-}" in
  install)
    cmd_install
    ;;
  backup)
    cmd_backup
    ;;
  reinstall)
    cmd_reinstall
    ;;
  update)
    cmd_update
    ;;
  status)
    cmd_status
    ;;
  uninstall)
    cmd_uninstall
    ;;
  *)
    echo "MBM v$VERSION"
    echo
    echo "Usage:"
    echo "  mbm install"
    echo "  mbm backup"
    echo "  mbm reinstall"
    echo "  mbm update"
    echo "  mbm status"
    echo "  mbm uninstall"
    ;;
esac
