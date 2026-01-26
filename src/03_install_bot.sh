#!/bin/bash

# Скрипт установки Telegram-бота (С поддержкой скрытых портов)

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Пожалуйста, запустите скрипт через sudo!${NC}"
  exit 1
fi

echo -e "${GREEN}=== УСТАНОВКА TELEGRAM БОТА ДЛЯ 3X-UI ===${NC}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BOT_SOURCE_DIR="$SCRIPT_DIR/../bot"
WORK_DIR="/opt/tg-bot"

if [ ! -d "$BOT_SOURCE_DIR" ]; then
    echo -e "${RED}❌ Ошибка: Не найдена папка с кодом бота!${NC}"
    exit 1
fi

# Читаем данные и ПОРТ
CRED_FILE="/root/.3xui_credentials"
if [ -f "$CRED_FILE" ]; then
    source "$CRED_FILE"
    echo "✅ Данные от панели 3x-ui найдены."
    
    # Если внутреннего порта нет в файле (старая установка), берем 2053
    if [ -z "$INTERNAL_PORT" ]; then
        INTERNAL_PORT=2053
    fi
else
    echo -e "${RED}❌ Файл $CRED_FILE не найден! Сначала установите панель 3x-ui.${NC}"
    exit 1
fi

echo ""
echo "Введите токен вашего бота (получить у @BotFather):"
if [ -t 0 ]; then
    read -p "Token: " BOT_TOKEN
else
    read -p "Token: " BOT_TOKEN < /dev/tty
fi

if [ -z "$BOT_TOKEN" ]; then
    echo -e "${RED}❌ Токен не может быть пустым!${NC}"
    exit 1
fi

echo "📂 Подготовка файлов..."
mkdir -p "$WORK_DIR"
cp -r "$BOT_SOURCE_DIR/"* "$WORK_DIR/"
cd "$WORK_DIR"

# Генерируем docker-compose
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  tg-bot:
    build: .
    container_name: tg-bot
    restart: always
    networks:
      - shared-network
    env_file:
      - .env
networks:
  shared-network:
    external: true
EOF

# Генерируем .env с правильным внутренним портом
cat > .env <<EOF
BOT_TOKEN=$BOT_TOKEN
XUI_URL=http://3x-ui:$INTERNAL_PORT
XUI_USER=$USER
XUI_PASS=$PASS
EOF

echo "🚀 Запуск контейнера..."
docker-compose down 2>/dev/null
docker-compose up -d --build

echo ""
echo "=========================================="
echo "✅ БОТ ОБНОВЛЕН И ЗАПУЩЕН!"
echo "Логи: docker logs -f tg-bot"
echo "=========================================="