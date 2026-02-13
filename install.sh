#!/usr/bin/env bash
set -e

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; CYN='\033[0;36m'
MAG='\033[0;35m'; WHT='\033[1;37m'; NC='\033[0m'
say(){ echo -e "${CYN}➜${NC} $*"; }
ok(){ echo -e "${GRN}✔${NC} $*"; }
err(){ echo -e "${RED}✖${NC} $*"; }
title(){ echo -e "${MAG}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${WHT}$*${NC}\n${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

if [ "$(id -u)" -ne 0 ]; then
  err "Run as root"
  exit 1
fi

title "Marzban Backup Manager — Installer"
say "Installing to: /usr/local/bin/mbm"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -m 755 "$SCRIPT_DIR/mbm" /usr/local/bin/mbm

ok "mbm installed ✅"
say "Now run: mbm install"
