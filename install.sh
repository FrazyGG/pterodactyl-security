#!/bin/bash
# ==============================================
# PTERODACTYL SECURITY INSTALLER
# ==============================================
# Cara pakai:
# curl -s https://raw.githubusercontent.com/ahmad62626/pterodactyl-security/main/install.sh | bash
# ==============================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════╗"
echo "║     PTERODACTYL SECURITY HARDENER INSTALLER       ║"
echo "║        Amankan Panel dari Serangan Hacker         ║"
echo "╚════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Cek root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Error: Jalankan sebagai root!${NC}"
    echo "   sudo su -"
    exit 1
fi

# Cek OS
if [ ! -f /etc/os-release ]; then
    echo -e "${RED}❌ Tidak bisa mendeteksi OS${NC}"
    exit 1
fi

. /etc/os-release
if [ "$ID" != "ubuntu" ]; then
    echo -e "${RED}❌ Script ini khusus untuk Ubuntu!${NC}"
    exit 1
fi

# Install curl jika belum ada
if ! command -v curl &> /dev/null; then
    apt-get update -qq && apt-get install curl -y -qq
fi

# Tentukan direktori install
INSTALL_DIR="/opt/pterodactyl-security"
mkdir -p $INSTALL_DIR/modules

echo -e "${YELLOW}📥 Mendownload script dari GitHub...${NC}"

# Download file utama
curl -s -o $INSTALL_DIR/pterodactyl-protect.sh https://raw.githubusercontent.com/ahmad62626/pterodactyl-security/main/pterodactyl-protect.sh

# Download modules
for module in firewall fail2ban panel-security database wings backup; do
    curl -s -o $INSTALL_DIR/modules/${module}.sh https://raw.githubusercontent.com/ahmad62626/pterodactyl-security/main/modules/${module}.sh
    chmod +x $INSTALL_DIR/modules/${module}.sh
done

# Cek download berhasil
if [ ! -f "$INSTALL_DIR/pterodactyl-protect.sh" ]; then
    echo -e "${RED}❌ Gagal mendownload script!${NC}"
    exit 1
fi

# Beri izin execute
chmod +x $INSTALL_DIR/pterodactyl-protect.sh

# Buat symlink
ln -sf $INSTALL_DIR/pterodactyl-protect.sh /usr/local/bin/protect-panel

echo -e "${GREEN}✅ Installasi selesai!${NC}"
echo ""
echo -e "${YELLOW}📌 Cara menggunakan:${NC}"
echo "   ketik: ${GREEN}protect-panel${NC}  (dari mana saja)"
echo ""
echo -e "${CYAN}Menjalankan Pterodactyl Security Hardener...${NC}"
sleep 2

# Jalankan script
$INSTALL_DIR/pterodactyl-protect.sh
