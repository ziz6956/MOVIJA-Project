#!/bin/bash

# curl -Ls "https://gist.githubusercontent.com/ziz6956/6c51dfaca88e9903d945d1ecb2f5e18f/raw/install_3xui.sh?v=$(date +%s)" | sudo bash

set -e

echo "--- [1/4] Установка зависимостей..."

# Настройка сети
sudo docker network create shared-network 2>/dev/null || true

# Выбор случайного порта для панели
PANEL_PORT=$((RANDOM % 45000 + 20000))

# Создание docker-compose
mkdir -p ~/3x-ui && cd ~/3x-ui
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  3x-ui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: 3x-ui
    restart: always
    networks:
      - shared-network
    volumes:
      - ./db/:/etc/x-ui/
      - ./cert/:/root/cert/
    environment:
      XRAY_VMESS_AEAD_FORCED: "false"
    ports:
      - "${PANEL_PORT}:2053"
      - "443:443"
      - "10000-10010:10000-10010"
networks:
  shared-network:
    external: true
EOF

echo "--- [2/4] Запуск контейнера..."
sudo docker-compose up -d

echo "--- [3/4] Генерация учетных данных..."
NEW_USER=$(pwgen -A 8 1)
NEW_PASS=$(pwgen -s 16 1)

# СОХРАНЕНИЕ В ФАЙЛ (То, о чем вы просили)
CONFIG_FILE="/root/.3xui_credentials"
echo "URL=\"http://127.0.0.1:$PANEL_PORT\"" > "$CONFIG_FILE"
echo "USER=\"$NEW_USER\"" >> "$CONFIG_FILE"
echo "PASS=\"$NEW_PASS\"" >> "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

echo "--- [4/4] Настройка панели..."
sleep 5
sudo docker exec 3x-ui ./x-ui setting -username "$NEW_USER" -password "$NEW_PASS"
sudo docker restart 3x-ui

echo "=========================================="
echo "✅ УСТАНОВКА ЗАВЕРШЕНА"
echo "Данные сохранены в $CONFIG_FILE"
echo "URL: http://$(curl -s http://checkip.amazonaws.com):$PANEL_PORT"
echo "Username: $NEW_USER / Password: $NEW_PASS"
echo "=========================================="