# 🛡️ PTERODACTYL SECURITY HARDENER

![Version](https://img.shields.io/badge/version-3.0-green)
![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04|22.04|24.04-orange)
![Pterodactyl](https://img.shields.io/badge/Pterodactyl-1.0+-blue)
![License](https://img.shields.io/badge/license-MIT-red)

## 📌 **DESKRIPSI**
Script keamanan lengkap untuk **Panel Pterodactyl** yang melindungi dari:
- 🔴 Serangan brute force (percobaan login berulang)
- 🔴 Pencurian file `.env` (berisi password database)
- 🔴 Eksploitasi API Wings
- 🔴 Port scanning dan DDoS kecil
- 🔴 Akses tidak sah ke database
- 🔴 File backdoor/shell

## ✨ **FITUR LENGKAP**

### 🔒 **Fitur Keamanan**
| No | Fitur | Keterangan |
|----|-------|------------|
| 1 | **Firewall Hardening** | Blokir port tidak perlu, rate limiting |
| 2 | **Fail2Ban Integration** | Auto-ban IP mencurigakan |
| 3 | **Panel Security** | Permission benar, debug off, env protection |
| 4 | **Database Security** | Hapus user anonim, secure root |
| 5 | **Wings Protection** | Secure config, API protection |
| 6 | **File Scanner** | Deteksi backdoor/shell |
| 7 | **Auto Backup** | Backup sebelum perubahan |

### 📊 **Menu Interaktif**
- **Menu 1**: 🔒 Install semua proteksi (firewall + fail2ban + panel + db + wings)
- **Menu 2**: 🔓 Uninstall semua proteksi
- **Menu 3**: 📊 Cek status keamanan (firewall, fail2ban, panel)
- **Menu 4**: 🛡️ Update Panel Pterodactyl ke versi terbaru
- **Menu 5**: 📁 Lihat daftar backup
- **Menu 6**: 🔄 Restore backup (manual)
- **Menu 0**: 🚪 Keluar

## 🚀 **CARA INSTALL**

### **Metode 1: 1 Perintah (Paling Mudah)**
```bash
curl -s https://raw.githubusercontent.com/FrazyGG/pterodactyl-security/main/install.sh | bash
