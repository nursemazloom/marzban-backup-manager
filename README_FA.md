<div align="center">

# 🚀 Marzban Backup Manager (MBM)

مدیریت حرفه‌ای بکاپ و ریستور مرزبان با ارسال به تلگرام

🇬🇧 **[English Version](README.md)**

</div>

---

## ✨ امکانات

- بکاپ کامل از Marzban
- تاریخ شمسی (Jalali) در نام فایل
- ارسال خودکار به تلگرام همراه با کپشن کامل
- پشتیبانی از SOCKS5 (مناسب سرور ایران)
- زمان‌بندی هوشمند کرون
- دستورات Version / Status / Update
- حذف کامل با یک دستور

---

## 📦 نصب با یک دستور

    bash <(curl -sL https://raw.githubusercontent.com/nursemazloom/marzban-backup-manager/main/install.sh)

---

## 📖 دستورات

    mbm install
    mbm backup
    mbm restore <file>
    mbm status
    mbm version
    mbm update
    mbm uninstall
    mbm help

---

## 🛠 رفع خطا

### خطای syntax error near unexpected token ')'

اگر این خطا را دیدید یعنی فایل mbm ناقص دانلود شده.

دوباره نصب کنید:

    sudo curl -fsSL https://raw.githubusercontent.com/nursemazloom/marzban-backup-manager/main/mbm -o /usr/local/bin/mbm
    sudo chmod +x /usr/local/bin/mbm
    sudo sed -i 's/\r$//' /usr/local/bin/mbm

سپس بررسی کنید:

    mbm version

---

## 📂 مسیر بکاپ

بکاپ‌ها در مسیر زیر ذخیره می‌شوند:

    /opt/marzban/backup

---

## ❤️ توسعه داده شده برای مدیریت حرفه‌ای مرزبان

