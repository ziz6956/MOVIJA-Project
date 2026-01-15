#!/usr/bin/env bash
#
# Quick start command / Команда быстрого запуска:
# wget -O setup.sh https://gist.githubusercontent.com/ziz6956/272eb4fdf409ba45d90fa582583f37cc/raw/setup.sh && chmod +x setup.sh && ./setup.sh
#
# Automatic VPS Setup Script (Ubuntu 20.04/22.04/24.04)
# Скрипт автоматической настройки VPS (Ubuntu 20.04/22.04/24.04)
#
# Actions: Update, SWAP 2GB, TCP BBR, UFW, Auto-Credentials, Auto-Reboot
# Делает: Update, SWAP 2GB, TCP BBR, UFW, Авто-пароли, Авто-ребут
#
# Author: ziz6956

# Strict mode
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: Please run this script as root."
  exit 1
fi

# Function: Wait for dpkg/apt lock to be released
wait_for_apt_lock() {
  local max_wait=600  # Maximum wait time in seconds (10 minutes)
  local elapsed=0
  local lock_files=(
    "/var/lib/apt/lists/lock"
    "/var/cache/apt/archives/lock"
    "/var/lib/dpkg/lock"
    "/var/lib/dpkg/lock-frontend"
  )
  
  while true; do
    # Check if any lock file is held
    local locked=0
    for lock_file in "${lock_files[@]}"; do
      if [ -f "$lock_file" ]; then
        if fuser "$lock_file" >/dev/null 2>&1; then
          locked=1
          break
        fi
      fi
    done
    
    if [ $locked -eq 0 ]; then
      break  # All locks released
    fi
    
    if [ $elapsed -ge $max_wait ]; then
      echo ""
      echo "ERROR: APT lock held for too long (>10 minutes)."
      echo "Trying to force-unlock..."
      
      # Kill any hung apt/dpkg processes
      pkill -9 -f "apt-get|apt|dpkg" 2>/dev/null || true
      sleep 2
      
      # Remove lock files forcefully
      rm -f /var/lib/apt/lists/lock 2>/dev/null || true
      rm -f /var/cache/apt/archives/lock 2>/dev/null || true
      rm -f /var/lib/dpkg/lock 2>/dev/null || true
      rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
      
      echo "Lock files removed. Proceeding..."
      break
    fi
    
    if [ $((elapsed % 30)) -eq 0 ]; then
      echo "--- Waiting for apt/dpkg to finish (${elapsed}s / ${max_wait}s)..."
    fi
    
    sleep 3
    elapsed=$((elapsed + 3))
  done
  
  if [ $elapsed -gt 0 ]; then
    echo "--- APT lock ready after ${elapsed} seconds."
  fi
}

# Display startup banner
echo "==========================================="
echo " STARTING AUTOMATIC SERVER SETUP"
echo " НАЧАЛО АВТОМАТИЧЕСКОЙ НАСТРОЙКИ СЕРВЕРА"
echo "==========================================="
echo ""
# ------------------------------------------------------------------
# 1. SYSTEM UPDATE & TOOLS
# ------------------------------------------------------------------
echo ""
echo "--- [1/6] Updating packages and installing tools..."
wait_for_apt_lock
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y
# curl & wget - Network downloaders (Скачивание файлов)
# dnsutils - DNS testing tools (dig, nslookup для проверки доменов)
# docker.io & docker-compose - Container platform (Запуск контейнеров)
# fail2ban - Protect SSH (Защита от брутфорса)
# git - Version control system (Для клонирования репозиториев)
# htop - Interactive process viewer (Мониторинг процессов)
# jq - JSON processor (Критически важно для API скриптов)
# mtr-tiny - Network diagnostics (Трассировка сети при лагах)
# ncdu - Disk usage analyzer (Анализ занятого места)
# openssl - Crypto tools (Генерация ключей)
# pwgen - Password generator (Генерация паролей)
# ufw - Uncomplicated Firewall (Настройка фаервола)
# zabbix-agent - Hardware monitoring agent (Агент мониторинга хоста)
apt-get install -y curl dnsutils docker-compose docker.io fail2ban git htop jq mtr-tiny ncdu openssl pwgen ufw wget
echo "System updated."

# Enable Docker on boot
systemctl enable --now docker

# Create shared Docker network
docker network create shared-network 2>/dev/null || true

# ------------------------------------------------------------------
# 2. ZABBIX AGENT INSTALLATION (Official Repo)
# ------------------------------------------------------------------
echo ""
echo "--- [2/6] Installing Zabbix Agent 7.0 (LTS)..."

# Ссылка на пакет репозитория для Ubuntu 24.04 (Noble)
ZABBIX_DEB="zabbix-release_7.0-2+ubuntu24.04_all.deb"
ZABBIX_URL="https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/$ZABBIX_DEB"

# Скачиваем и ставим репозиторий
wget -q "$ZABBIX_URL" -O "$ZABBIX_DEB"
dpkg -i "$ZABBIX_DEB"
rm -f "$ZABBIX_DEB"

# Обновляем списки (теперь Zabbix доступен) и ставим агент
apt-get update -q
apt-get install -y zabbix-agent

# Автозапуск
systemctl enable zabbix-agent
systemctl restart zabbix-agent
echo "Zabbix Agent 7.0 installed."

# ------------------------------------------------------------------
# 3. SWAP CONFIGURATION (2GB)
# ------------------------------------------------------------------
echo ""
echo "--- [3/6] Checking and creating SWAP..."
if grep -q "swapfile" /etc/fstab; then
  echo "SWAP already exists, skipping."
else
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
  echo "SWAP file (2GB) created."
fi

# ------------------------------------------------------------------
# 4. BBR CONFIGURATION
# ------------------------------------------------------------------
echo ""
echo "--- [4/6] Enabling Google BBR..."
SYSCTL_CONF="/etc/sysctl.conf"
if ! grep -q "net.core.default_qdisc=fq" "$SYSCTL_CONF"; then
  echo "net.core.default_qdisc=fq" >> "$SYSCTL_CONF"
fi
if ! grep -q "net.ipv4.tcp_congestion_control=bbr" "$SYSCTL_CONF"; then
  echo "net.ipv4.tcp_congestion_control=bbr" >> "$SYSCTL_CONF"
fi
sysctl -p
echo "BBR activated."

# ------------------------------------------------------------------
# 5. SECURITY (UFW)
# ------------------------------------------------------------------
echo ""
echo "--- [5/6] Configuring Firewall (UFW)..."
ufw --force reset > /dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw --force enable
echo "Firewall enabled (Port 22 Open)."

# ------------------------------------------------------------------
# 6. USER & PASSWORD GENERATION
# ------------------------------------------------------------------
echo ""
echo "--- [6/6] Creating User & Generating Passwords..."
echo "--- [6/6] Создание пользователя и генерация паролей..."

# 1. Ask for username
echo ""
read -p "Enter name for new sudo user (e.g. manager): / Введите имя нового пользователя: " NEW_USERNAME

# Check if user exists
if id "$NEW_USERNAME" &>/dev/null; then
    echo "User $NEW_USERNAME already exists. Skipping creation."
else
    # 2. Generate secure passwords using pwgen (Safer for scripts)
    # Генерируем пароли через pwgen (12 символов, 1 штука, безопасный режим)
    ROOT_PASS=$(pwgen -s 12 1)
    USER_PASS=$(pwgen -s 12 1)

    # 3. Set Root password
    echo "root:$ROOT_PASS" | chpasswd

    # 4. Create new user and add to sudo group
    useradd -m -s /bin/bash -G sudo "$NEW_USERNAME"
    echo "$NEW_USERNAME:$USER_PASS" | chpasswd
    
    # 5. Save credentials to display them later
    echo "--------------------------------------------------" > /root/credentials_setup.txt
    echo "SERVER CREDENTIALS / ДОСТУПЫ К СЕРВЕРУ" >> /root/credentials_setup.txt
    echo "--------------------------------------------------" >> /root/credentials_setup.txt
    echo "IP Address:   $(hostname -I | awk '{print $1}')" >> /root/credentials_setup.txt
    echo "Root Pass:    $ROOT_PASS" >> /root/credentials_setup.txt
    echo "--------------------------------------------------" >> /root/credentials_setup.txt
    echo "New User:     $NEW_USERNAME" >> /root/credentials_setup.txt
    echo "User Pass:    $USER_PASS" >> /root/credentials_setup.txt
    echo "--------------------------------------------------" >> /root/credentials_setup.txt
    echo "SAVE THIS NOW! / СОХРАНИТЕ ЭТО ПРЯМО СЕЙЧАС!" >> /root/credentials_setup.txt
    echo "After reboot, login as: $NEW_USERNAME" >> /root/credentials_setup.txt
fi

# ------------------------------------------------------------------
# COMPLETION & OUTPUT
# ------------------------------------------------------------------
echo ""
echo "=========================================================="
echo " SETUP COMPLETE! / УСТАНОВКА ЗАВЕРШЕНА!"
echo "=========================================================="
echo ""
# Display credentials vividly
if [ -f /root/credentials_setup.txt ]; then
    cat /root/credentials_setup.txt
    # rm /root/credentials_setup.txt # Uncomment to auto-delete
else
    echo "User was not created (maybe existed)."
fi
echo ""
echo "=========================================================="
echo " IMPORTANT: Copy the passwords above BEFORE rebooting!"
echo " ВАЖНО: Скопируйте пароли выше ПЕРЕД перезагрузкой!"
echo "=========================================================="
echo ""

read -p "Did you copy the passwords? Reboot now? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Rebooting..."
    reboot
else
    echo "Please reboot manually: 'reboot'"
fi