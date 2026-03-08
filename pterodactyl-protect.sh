#!/bin/bash
# ==============================================
# PTERODACTYL SECURITY HARDENER
# ==============================================
# File: /opt/pterodactyl-security/pterodactyl-protect.sh
# Version: 3.0
# ==============================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

VERSION="3.0"
PANEL_DIR="/var/www/pterodactyl"
WINGS_CONFIG="/etc/pterodactyl/config.yml"
BACKUP_DIR="/root/pterodactyl-security-backup"
MODULES_DIR="/opt/pterodactyl-security/modules"

# ==============================================
# CEK ROOT
# ==============================================
cek_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❌ Error: Script ini harus dijalankan sebagai root!${NC}"
        exit 1
    fi
}

# ==============================================
# CEK PTERODACTYL
# ==============================================
cek_pterodactyl() {
    echo -e "${YELLOW}🔍 Mengecek instalasi Pterodactyl...${NC}"
    
    if [ ! -d "$PANEL_DIR" ]; then
        echo -e "${RED}❌ Pterodactyl Panel tidak ditemukan!${NC}"
        echo "   Pastikan Pterodactyl terinstall di $PANEL_DIR"
        exit 1
    fi
    
    if [ ! -f "$PANEL_DIR/.env" ]; then
        echo -e "${RED}❌ File .env tidak ditemukan!${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Pterodactyl Panel ditemukan${NC}"
}

# ==============================================
# BACKUP OTOMATIS
# ==============================================
buat_backup() {
    echo -e "${YELLOW}💾 Membuat backup Pterodactyl...${NC}"
    
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_PATH="${BACKUP_DIR}/backup-${TIMESTAMP}"
    mkdir -p "$BACKUP_PATH"
    
    # Backup .env
    cp "$PANEL_DIR/.env" "$BACKUP_PATH/env.backup" 2>/dev/null
    echo "  ✓ File .env"
    
    # Backup database
    if [ -f "$PANEL_DIR/.env" ]; then
        DB_HOST=$(grep DB_HOST "$PANEL_DIR/.env" | cut -d '=' -f2)
        DB_PORT=$(grep DB_PORT "$PANEL_DIR/.env" | cut -d '=' -f2)
        DB_DATABASE=$(grep DB_DATABASE "$PANEL_DIR/.env" | cut -d '=' -f2)
        DB_USERNAME=$(grep DB_USERNAME "$PANEL_DIR/.env" | cut -d '=' -f2)
        DB_PASSWORD=$(grep DB_PASSWORD "$PANEL_DIR/.env" | cut -d '=' -f2)
        
        if [ ! -z "$DB_PASSWORD" ]; then
            mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" > "$BACKUP_PATH/database.sql" 2>/dev/null
            echo "  ✓ Database dump"
        fi
    fi
    
    # Backup Wings config
    if [ -f "$WINGS_CONFIG" ]; then
        cp "$WINGS_CONFIG" "$BACKUP_PATH/wings.backup"
        echo "  ✓ Wings config"
    fi
    
    # Backup Nginx config
    if [ -f /etc/nginx/sites-available/pterodactyl.conf ]; then
        cp /etc/nginx/sites-available/pterodactyl.conf "$BACKUP_PATH/nginx.backup"
        echo "  ✓ Nginx config"
    fi
    
    echo -e "${GREEN}✓ Backup selesai di: $BACKUP_PATH${NC}"
    echo "$BACKUP_PATH" > /tmp/last_backup
}

# ==============================================
# INSTALL DEPENDENSI
# ==============================================
install_deps() {
    echo -e "${YELLOW}[1/7] Menginstall dependensi keamanan...${NC}"
    
    apt-get update -qq
    apt-get install -y \
        iptables \
        iptables-persistent \
        fail2ban \
        curl \
        wget \
        unzip \
        zip \
        -qq
    
    echo -e "${GREEN}✓ Dependensi terinstall${NC}"
}

# ==============================================
# KONFIGURASI FIREWALL
# ==============================================
setup_firewall() {
    echo -e "${YELLOW}[2/7] Konfigurasi Firewall untuk Pterodactyl...${NC}"
    
    # Backup rules lama
    iptables-save > /tmp/iptables.backup 2>/dev/null
    
    # Flush existing rules
    iptables -F
    iptables -X
    
    # Default policies
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    
    # Allow established connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Allow SSH (standard port 22)
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    
    # Allow Panel ports
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT   # HTTP
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT  # HTTPS
    
    # Allow Wings
    iptables -A INPUT -p tcp --dport 8080 -j ACCEPT  # Wings API
    
    # Allow SFTP
    iptables -A INPUT -p tcp --dport 2022 -j ACCEPT  # SFTP
    
    # Allow MySQL/MariaDB (jika local)
    iptables -A INPUT -p tcp --dport 3306 -s 127.0.0.1 -j ACCEPT
    
    # Allow Redis (jika local)
    iptables -A INPUT -p tcp --dport 6379 -s 127.0.0.1 -j ACCEPT
    
    # Rate limiting untuk SSH
    iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
    iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 5 -j DROP
    
    # Rate limiting untuk Panel
    iptables -A INPUT -p tcp --dport 80 -m state --state NEW -m recent --set
    iptables -A INPUT -p tcp --dport 80 -m state --state NEW -m recent --update --seconds 60 --hitcount 100 -j DROP
    iptables -A INPUT -p tcp --dport 443 -m state --state NEW -m recent --set
    iptables -A INPUT -p tcp --dport 443 -m state --state NEW -m recent --update --seconds 60 --hitcount 100 -j DROP
    
    # Block port scanning
    iptables -A INPUT -m state --state NEW -p tcp --tcp-flags SYN,ACK SYN,ACK -m recent --name portscan --set -j DROP
    
    # Simpan aturan
    netfilter-persistent save
    
    echo -e "${GREEN}✓ Firewall dikonfigurasi${NC}"
}

# ==============================================
# KONFIGURASI FAIL2BAN
# ==============================================
setup_fail2ban() {
    echo -e "${YELLOW}[3/7] Konfigurasi Fail2Ban untuk Pterodactyl...${NC}"
    
    # Buat filter untuk Panel
    cat > /etc/fail2ban/filter.d/pterodactyl-panel.conf << 'EOF'
[Definition]
failregex = .*Invalid username or password.*IP: <HOST>.*$
            .*Failed login attempt.*from <HOST>.*$
            .*Two-factor authentication failed.*from <HOST>.*$
            .*Invalid API key.*from <HOST>.*$
            .*Too many login attempts.*IP: <HOST>.*$
ignoreregex =
EOF

    # Buat filter untuk Wings
    cat > /etc/fail2ban/filter.d/pterodactyl-wings.conf << 'EOF'
[Definition]
failregex = .*Unauthorized request from <HOST>.*$
            .*Invalid authentication from <HOST>.*$
            .*Failed authentication attempt.*<HOST>.*$
            .*Invalid token.*from <HOST>.*$
ignoreregex =
EOF

    # Buat filter untuk Adminer/phppgadmin (serangan umum)
    cat > /etc/fail2ban/filter.d/adminer.conf << 'EOF'
[Definition]
failregex = ^<HOST> .* "GET .*/adminer/.*" 404
            ^<HOST> .* "GET .*/phpmyadmin/.*" 404
            ^<HOST> .* "GET .*/pma/.*" 404
            ^<HOST> .* "GET .*/db/.*" 404
ignoreregex =
EOF

    # Konfigurasi jail.local
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1
banaction = iptables-multiport

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400

[pterodactyl-panel]
enabled = true
port = http,https
filter = pterodactyl-panel
logpath = $PANEL_DIR/storage/logs/laravel-*.log
maxretry = 5
bantime = 3600

[pterodactyl-wings]
enabled = true
port = 8080
filter = pterodactyl-wings
logpath = /var/log/wings.log
maxretry = 3
bantime = 3600

[adminer]
enabled = true
port = http,https
filter = adminer
logpath = /var/log/nginx/access.log
maxretry = 1
bantime = 86400
EOF

    # Restart fail2ban
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    echo -e "${GREEN}✓ Fail2Ban dikonfigurasi${NC}"
}

# ==============================================
# KEAMANAN PANEL (ENV & CONFIG)
# ==============================================
secure_panel() {
    echo -e "${YELLOW}[4/7] Mengamankan Panel Pterodactyl...${NC}"
    
    cd $PANEL_DIR
    
    # 1. Set permission yang benar
    echo "  ⚡ Set permission..."
    chown -R www-data:www-data $PANEL_DIR
    chmod -R 755 $PANEL_DIR/storage
    chmod -R 755 $PANEL_DIR/bootstrap/cache
    chmod 640 $PANEL_DIR/.env
    
    # 2. Generate key baru (opsional, komentari jika tidak ingin)
    # php artisan key:generate --force
    
    # 3. Set APP_ENV ke production
    sed -i 's/APP_ENV=.*/APP_ENV=production/' $PANEL_DIR/.env
    sed -i 's/APP_DEBUG=.*/APP_DEBUG=false/' $PANEL_DIR/.env
    
    # 4. Set session dan cookie security
    sed -i 's/SESSION_SECURE_COOKIE=.*/SESSION_SECURE_COOKIE=true/' $PANEL_DIR/.env
    sed -i 's/TRUSTED_PROXIES=.*/TRUSTED_PROXIES="*"/' $PANEL_DIR/.env
    
    # 5. Disable registration jika tidak diperlukan
    # php artisan p:settings:register false
    
    # 6. Cache config
    php artisan config:cache
    php artisan view:cache
    php artisan route:cache
    
    echo -e "${GREEN}✓ Panel diamankan${NC}"
}

# ==============================================
# KEAMANAN DATABASE
# ==============================================
secure_database() {
    echo -e "${YELLOW}[5/7] Mengamankan Database...${NC}"
    
    if ! command -v mysql &> /dev/null; then
        echo -e "${RED}  ✗ MySQL tidak ditemukan, skip${NC}"
        return
    fi
    
    # Ambil kredensial dari .env
    source $PANEL_DIR/.env
    
    # Jalankan perintah keamanan MySQL
    mysql -u root <<EOF
-- Hapus database test
DROP DATABASE IF EXISTS test;

-- Hapus user anonymous
DELETE FROM mysql.user WHERE User='';

-- Set password root kuat (disarankan manual)
-- ALTER USER 'root'@'localhost' IDENTIFIED BY 'password-kuat';

-- Flush privileges
FLUSH PRIVILEGES;
EOF
    
    echo -e "${GREEN}✓ Database diamankan${NC}"
}

# ==============================================
# KEAMANAN WINGS
# ==============================================
secure_wings() {
    echo -e "${YELLOW}[6/7] Mengamankan Wings...${NC}"
    
    if [ ! -f "$WINGS_CONFIG" ]; then
        echo -e "${RED}  ✗ Wings tidak ditemukan, skip${NC}"
        return
    fi
    
    # Backup config
    cp "$WINGS_CONFIG" "$WINGS_CONFIG.bak"
    
    # Set permission
    chmod 600 "$WINGS_CONFIG"
    chown root:root "$WINGS_CONFIG"
    
    # Restart wings
    systemctl restart wings
    
    echo -e "${GREEN}✓ Wings diamankan${NC}"
}

# ==============================================
# CEK VULNERABILITIES
# ==============================================
check_vulnerabilities() {
    echo -e "${YELLOW}[7/7] Mengecek vulnerabilities...${NC}"
    
    # Cek versi Panel
    if [ -f "$PANEL_DIR/config/app.php" ]; then
        PANEL_VERSION=$(grep "'version'" $PANEL_DIR/config/app.php | cut -d"'" -f4)
        echo "  📊 Panel version: $PANEL_VERSION"
        
        # Cek versi terbaru (sederhana)
        LATEST=$(curl -s https://api.github.com/repos/pterodactyl/panel/releases/latest | grep tag_name | cut -d'"' -f4)
        if [ "$PANEL_VERSION" != "$LATEST" ]; then
            echo -e "  ${RED}⚠️ Panel tidak update! Latest: $LATEST${NC}"
        else
            echo -e "  ${GREEN}✓ Panel sudah update${NC}"
        fi
    fi
    
    # Cek file mencurigakan
    echo "  🔍 Scanning file mencurigakan..."
    find $PANEL_DIR -type f -name "*.php" -exec grep -l "eval(base64_decode\|system(\|shell_exec(\|passthru(" {} \; 2>/dev/null | while read file; do
        echo -e "  ${RED}⚠️ Mencurigakan: $file${NC}"
    done
    
    # Cek permission
    echo "  🔍 Cek permission .env:"
    ENV_PERM=$(stat -c "%a" $PANEL_DIR/.env)
    if [ "$ENV_PERM" != "640" ]; then
        echo -e "  ${RED}⚠️ Permission .env salah (seharusnya 640)${NC}"
    else
        echo -e "  ${GREEN}✓ Permission .env OK${NC}"
    fi
    
    echo -e "${GREEN}✓ Vulnerability check selesai${NC}"
}

# ==============================================
# INSTALL SEMUA
# ==============================================
install_all() {
    clear
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════════════════════╗"
    echo "║     INSTALL PTERODACTYL SECURITY HARDENER         ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    cek_root
    cek_pterodactyl
    buat_backup
    
    install_deps
    setup_firewall
    setup_fail2ban
    secure_panel
    secure_database
    secure_wings
    check_vulnerabilities
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✅ PTERODACTYL TELAH DIAMANKAN     ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}📁 Backup: $BACKUP_PATH${NC}"
    echo -e "${YELLOW}🔧 Cek status: fail2ban-client status${NC}"
    echo -e "${YELLOW}📊 Firewall: iptables -L -v${NC}"
    echo ""
    echo -e "${CYAN}Tekan Enter untuk kembali ke menu...${NC}"
    read
}

# ==============================================
# UNINSTALL
# ==============================================
uninstall_all() {
    clear
    echo -e "${RED}"
    echo "╔════════════════════════════════════════════════════╗"
    echo "║     UNINSTALL PTERODACTYL SECURITY                ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    cek_root
    
    echo -e "${YELLOW}⚠️  Yakin ingin menghapus semua proteksi? (y/n)${NC}"
    read confirm
    
    if [ "$confirm" != "y" ]; then
        return
    fi
    
    buat_backup
    
    echo -e "${YELLOW}[1/4] Mengembalikan firewall...${NC}"
    iptables -F
    iptables -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    netfilter-persistent save
    
    echo -e "${YELLOW}[2/4] Menonaktifkan fail2ban...${NC}"
    systemctl stop fail2ban
    systemctl disable fail2ban
    
    echo -e "${YELLOW}[3/4] Mengembalikan permission...${NC}"
    chown -R www-data:www-data $PANEL_DIR
    chmod 644 $PANEL_DIR/.env
    
    echo -e "${YELLOW}[4/4] Restart services...${NC}"
    systemctl restart nginx
    systemctl restart php8.*-fpm 2>/dev/null
    systemctl restart wings 2>/dev/null
    
    echo -e "${GREEN}✅ Proteksi telah dihapus${NC}"
    echo ""
    echo -e "${CYAN}Tekan Enter untuk kembali ke menu...${NC}"
    read
}

# ==============================================
# CEK STATUS
# ==============================================
cek_status() {
    clear
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════╗"
    echo "║        STATUS KEAMANAN PTERODACTYL                ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo ""
    echo -e "${YELLOW}📊 FIREWALL STATUS:${NC}"
    echo "----------------------------------------"
    iptables -L INPUT -v | head -10
    
    echo ""
    echo -e "${YELLOW}📊 FAIL2BAN STATUS:${NC}"
    echo "----------------------------------------"
    fail2ban-client status | grep "Jail list"
    
    echo ""
    echo -e "${YELLOW}📊 PANEL STATUS:${NC}"
    echo "----------------------------------------"
    if [ -f "$PANEL_DIR/.env" ]; then
        APP_ENV=$(grep APP_ENV $PANEL_DIR/.env | cut -d'=' -f2)
        APP_DEBUG=$(grep APP_DEBUG $PANEL_DIR/.env | cut -d'=' -f2)
        echo "  APP_ENV: $APP_ENV"
        echo "  APP_DEBUG: $APP_DEBUG"
    fi
    
    echo ""
    echo -e "${YELLOW}📊 SERVICE STATUS:${NC}"
    echo "----------------------------------------"
    systemctl is-active nginx --quiet && echo "  ✓ Nginx: RUNNING" || echo "  ✗ Nginx: STOPPED"
    systemctl is-active mysql --quiet && echo "  ✓ MySQL: RUNNING" || echo "  ✗ MySQL: STOPPED"
    systemctl is-active wings --quiet && echo "  ✓ Wings: RUNNING" || echo "  ✗ Wings: STOPPED"
    
    echo ""
    echo -e "${CYAN}Tekan Enter untuk kembali ke menu...${NC}"
    read
}

# ==============================================
# RESTORE BACKUP
# ==============================================
restore_backup() {
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════╗"
    echo "║        RESTORE BACKUP PTERODACTYL                 ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}❌ Tidak ada backup ditemukan${NC}"
        read
        return
    fi
    
    echo -e "${YELLOW}Daftar backup tersedia:${NC}"
    ls -la $BACKUP_DIR | grep "backup-" | nl
    
    echo ""
    echo -e "Pilih nomor backup: "
    read nomor
    
    # Logic restore (sederhana)
    echo -e "${RED}Fitur restore manual, silakan cek folder backup${NC}"
    echo "  Backup location: $BACKUP_DIR"
    
    echo ""
    echo -e "${CYAN}Tekan Enter untuk kembali ke menu...${NC}"
    read
}

# ==============================================
# UPDATE PANEL
# ==============================================
update_panel() {
    clear
    echo -e "${PURPLE}"
    echo "╔════════════════════════════════════════════════════╗"
    echo "║        UPDATE PTERODACTYL PANEL                   ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    cek_root
    cek_pterodactyl
    buat_backup
    
    cd $PANEL_DIR
    
    echo -e "${YELLOW}📥 Mendownload update terbaru...${NC}"
    php artisan down
    
    curl -L https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz | tar -xzv
    
    chmod -R 755 storage/* bootstrap/cache
    
    composer install --no-dev --optimize-autoloader
    
    php artisan view:clear
    php artisan config:clear
    
    php artisan migrate --seed --force
    
    chown -R www-data:www-data $PANEL_DIR
    
    php artisan up
    
    echo -e "${GREEN}✅ Panel berhasil diupdate${NC}"
    echo ""
    echo -e "${CYAN}Tekan Enter untuk kembali ke menu...${NC}"
    read
}

# ==============================================
# MENU UTAMA
# ==============================================
menu() {
    while true; do
        clear
        echo -e "${CYAN}"
        echo "╔════════════════════════════════════════════════════╗"
        echo "║     PTERODACTYL SECURITY HARDENER v$VERSION        ║"
        echo "║        Amankan Panel dari Serangan Hacker         ║"
        echo "╠════════════════════════════════════════════════════╣"
        echo "║                                                    ║"
        echo "║  ${GREEN}[1]${NC} 🔒 INSTALL SEMUA PROTEKSI              ║"
        echo "║  ${RED}[2]${NC} 🔓 UNINSTALL PROTEKSI                    ║"
        echo "║  ${BLUE}[3]${NC} 📊 CEK STATUS KEAMANAN                  ║"
        echo "║  ${YELLOW}[4]${NC} 🛡️  UPDATE PANEL PTERODACTYL           ║"
        echo "║  ${CYAN}[5]${NC} 📁 LIHAT BACKUP                         ║"
        echo "║  ${PURPLE}[6]${NC} 🔄 RESTORE BACKUP                      ║"
        echo "║  ${RED}[0]${NC} 🚪 KELUAR                                ║"
        echo "║                                                    ║"
        echo "╚════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -n "Pilih menu [0-6]: "
        read pilihan
        
        case $pilihan in
            1) install_all ;;
            2) uninstall_all ;;
            3) cek_status ;;
            4) update_panel ;;
            5) ls -la $BACKUP_DIR 2>/dev/null || echo "Belum ada backup"; read ;;
            6) restore_backup ;;
            0) 
                echo -e "${GREEN}Terima kasih! Panel Anda lebih aman sekarang 🛡️${NC}"
                exit 0
                ;;
            *) 
                echo -e "${RED}Pilihan tidak valid!${NC}"
                sleep 1
                ;;
        esac
    done
}

# Jalankan menu
menu
