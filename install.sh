#!/usr/bin/env bash
set -e

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; CYN='\033[0;36m'
MAG='\033[0;35m'; WHT='\033[1;37m'; NC='\033[0m'
say(){ echo -e "${CYN}➜${NC} $*"; }
ok(){ echo -e "${GRN}✔${NC} $*"; }
warn(){ echo -e "${YLW}⚠${NC} $*"; }
err(){ echo -e "${RED}✖${NC} $*"; }
title(){ echo -e "${MAG}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${WHT}Marzban Backup Manager — Installer${NC}\n${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

REPO_RAW="https://raw.githubusercontent.com/nursemazloom/marzban-backup-manager/main"
BIN="/usr/local/bin/mbm"
TTY="/dev/tty"

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    if command -v sudo >/dev/null 2>&1; then
      sudo -E "$@"
    else
      err "sudo not found. Run as root."
      exit 1
    fi
  fi
}

title
say "Installing to: ${BIN}"

run_as_root mkdir -p /usr/local/bin

# --- MBM_DEP_INSTALL (required tools for mbm) ---
run_as_root bash -lc '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y tar gzip iproute2 ca-certificates >/dev/null 2>&1 || true
' || true
# --- /MBM_DEP_INSTALL ---

run_as_root curl -fsSL "${REPO_RAW}/mbm" -o "${BIN}"
run_as_root chmod +x "${BIN}"
ok "Installed successfully"

if [ "${1:-}" = "auto" ]; then
  echo
  say "Starting setup..."
  echo
  # Ensure interactive prompts always work
  if [ -c "$TTY" ]; then
    run_as_root bash -lc "mbm install" < "$TTY"
  else
    # fallback (rare)
    run_as_root mbm install
  fi
fi
