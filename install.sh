#!/usr/bin/env bash
set -e

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; CYN='\033[0;36m'
MAG='\033[0;35m'; WHT='\033[1;37m'; NC='\033[0m'

title(){
echo -e "${MAG}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${WHT}Marzban Backup Manager — Installer${NC}"
echo -e "${MAG}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

title

echo -e "${CYN}➜${NC} Installing to: /usr/local/bin/mbm"

curl -sL https://raw.githubusercontent.com/nursemazloom/marzban-backup-manager/main/mbm -o /usr/local/bin/mbm
chmod +x /usr/local/bin/mbm

echo -e "${GRN}✔ Installed successfully${NC}"

if [ "$1" = "auto" ]; then
    echo -e "\n${CYN}➜${NC} Starting setup...\n"
    sleep 1
    mbm install
fi
