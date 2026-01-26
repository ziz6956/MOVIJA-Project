#!/bin/bash

set -e

echo "--- [1/4] Установка зависимостей..."

# Настройка сети
sudo docker network create shared-network 2>/dev/null || true

# 1. Генерируем ДВА порта:
# PANEL_PORT - внешний порт (для входа из интернета)
# SAFE_PORT - внутренний порт (на котором реально висит процесс 3x-ui внутри докера)
PANEL_PORT=$((RANDOM % 15000 + 30000))  # 30000-45000
SAFE_PORT=$((RANDOM % 10000 + 50000))   # 50000-60000

echo "Внешний порт: $PANEL_PORT"
echo "Внутренний порт (скрытый): $SAFE_PORT"

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
      # Пробрасываем Внешний -> Внутренний
      - "${PANEL_PORT}:${SAFE_PORT}"
      - "443:443"
      # Порты для Reality/Shadowsocks
      - "10000-10010:10000-10010"
networks:
  shared-network:
    external: true
EOF

echo "--- [2/4] Запуск контейнера..."
sudo docker-compose up -d

echo "--- [3/4] Генерация учетных данных и настройка порта..."
NEW_USER=$(pwgen -A 8 1)
NEW_PASS=$(pwgen -s 16 1)

# СОХРАНЕНИЕ В ФАЙЛ
CONFIG_FILE="/root/.3xui_credentials"
echo "URL=\"http://127.0.0.1:$PANEL_PORT\"" > "$CONFIG_FILE"
echo "USER=\"$NEW_USER\"" >> "$CONFIG_FILE"
echo "PASS=\"$NEW_PASS\"" >> "$CONFIG_FILE"
# ! ВАЖНО: Сохраняем внутренний порт для бота
echo "INTERNAL_PORT=\"$SAFE_PORT\"" >> "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

echo "--- [4/4] Применение настроек..."
sleep 5
# Добавляем флаг -port, чтобы сама панель знала свой новый порт и не ругалась
sudo docker exec 3x-ui ./x-ui setting -username "$NEW_USER" -password "$NEW_PASS" -port "$SAFE_PORT"
# Обязательный рестарт, чтобы панель переехала на новый порт
sudo docker restart 3x-ui

echo "=========================================="
echo "✅ УСТАНОВКА ЗАВЕРШЕНА"
echo "Данные сохранены в $CONFIG_FILE"
echo "URL: http://$(curl -s http://checkip.amazonaws.com):$PANEL_PORT"
echo "Username: $NEW_USER / Password: $NEW_PASS"
echo "=========================================="