#!/bin/bash

GREEN='\033[0;32m'
NC='\033[0m'
WORK_DIR="/opt/tg-bot"
DATA_DIR="$WORK_DIR/data"
CONFIG_FILE="$DATA_DIR/config.json"
CLI_FILE="/usr/local/bin/tg-bot"

if [ ! -d "$WORK_DIR" ]; then
    echo "❌ Сначала установите бота (03_install_bot.sh)!"
    exit 1
fi

echo -e "${GREEN}=== АКТИВАЦИЯ МОДУЛЯ TEST-MODE ===${NC}"

# 1. Установка jq для работы с JSON
if ! command -v jq &> /dev/null; then
    apt-get update && apt-get install -y jq
fi

# 2. Создание папки data и конфига, если его нет
mkdir -p "$DATA_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
    # По умолчанию включаем test_mode: false, чтобы бот работал как обычно, пока вы не включите его
    echo '{"test_mode": false, "password": "admin"}' > "$CONFIG_FILE"
    chmod 666 "$CONFIG_FILE"
    echo "📄 Создан конфиг: $CONFIG_FILE"
fi

# 3. Обновление docker-compose (Добавляем volume ./data:/app/data)
# Это нужно, чтобы бот видел config.json
cd "$WORK_DIR"
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  tg-bot:
    build: .
    container_name: tg-bot
    restart: always
    networks:
      - shared-network
    volumes:
      - ./data:/app/data
    env_file:
      - .env
networks:
  shared-network:
    external: true
EOF

# 4. Создание CLI утилиты (tg-bot)
# Это удобная обертка для управления режимом через консоль
cat > "$CLI_FILE" << 'EOF'
#!/bin/bash
CONFIG_FILE="/opt/tg-bot/data/config.json"

if [ "$1" == "help" ] || [ -z "$1" ]; then
    echo "Управление ботом:"
    echo "  tg-bot test-mode enable    - Включить пароль"
    echo "  tg-bot test-mode disable   - Отключить пароль"
    echo "  tg-bot test-mode status    - Показать статус"
    exit 0
fi

if [ "$1" == "test-mode" ]; then
    case "$2" in
        enable)
            read -p "Новый пароль: " PWD
            tmp=$(mktemp)
            jq --arg pw "$PWD" '.test_mode = true | .password = $pw' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
            echo "✅ Тест-режим ВКЛЮЧЕН. Пароль: $PWD"
            ;;
        disable)
            tmp=$(mktemp)
            jq '.test_mode = false' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
            echo "🔓 Тест-режим ВЫКЛЮЧЕН."
            ;;
        status)
            cat "$CONFIG_FILE"
            echo ""
            ;;
    esac
fi
EOF
chmod +x "$CLI_FILE"

# 5. Применение изменений
echo "🚀 Перезапуск контейнера с новыми настройками..."
docker-compose down
docker-compose up -d --build

echo "✅ Модуль активирован."
echo "Используйте команду 'tg-bot' для управления."