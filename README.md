<div align="center">

# 🚀 Marzban Backup Manager (MBM)

Telegram Backup & Restore Manager for Marzban Panel

🇮🇷 **[مشاهده نسخه فارسی](README_FA.md)**

</div>

---

## ✨ Features

- Full Marzban backup & restore
- Jalali (Shamsi) timestamped backups
- Sends backup to Telegram with detailed caption
- Safe local IP detection (Iran compatible)
- Optional SOCKS5 proxy support
- Smart cron scheduling (minute-based)
- One-command restore + marzban restart
- Clean uninstall
- Version / Status / Update commands

---

## 📦 Installation (One-Line)

    bash <(curl -sL https://raw.githubusercontent.com/nursemazloom/marzban-backup-manager/main/install.sh)

---

## 📖 Commands

    mbm install
    mbm backup
    mbm restore <file>
    mbm status
    mbm version
    mbm update
    mbm uninstall
    mbm help

---

## 🛠 Troubleshooting

### syntax error near unexpected token ')'

This means your installed `mbm` file is corrupted (bad update or incomplete download).

Reinstall latest version:

    sudo curl -fsSL https://raw.githubusercontent.com/nursemazloom/marzban-backup-manager/main/mbm -o /usr/local/bin/mbm
    sudo chmod +x /usr/local/bin/mbm
    sudo sed -i 's/\r$//' /usr/local/bin/mbm

Then verify:

    mbm version

