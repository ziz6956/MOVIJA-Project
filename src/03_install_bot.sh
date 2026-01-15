#!/bin/bash

# curl -Ls "https://gist.githubusercontent.com/ziz6956/66bebbc204b89a0984ecfd0318b1179a/raw/install_bot.sh?v=$(date +%s)" | sudo bash

# Скрипт установки Telegram-бота для 3x-ui (VLESS Reality + Auto Inbound)
# Версия: 1.1 (Self-contained)

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Пожалуйста, запустите скрипт через sudo!${NC}"
  exit 1
fi

echo -e "${GREEN}=== УСТАНОВКА TELEGRAM БОТА ДЛЯ 3X-UI ===${NC}"

# 1. Поиск учетных данных 3x-ui
CRED_FILE="/root/.3xui_credentials"
if [ -f "$CRED_FILE" ]; then
    source "$CRED_FILE"
    echo "✅ Данные от панели 3x-ui найдены."
else
    echo -e "${RED}❌ Файл $CRED_FILE не найден! Сначала установите панель 3x-ui.${NC}"
    exit 1
fi

# 2. Запрос токена бота
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

# 3. Создание рабочей директории
WORK_DIR="/opt/tg-bot"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "📂 Генерация файлов проекта..."

# --- ГЕНЕРАЦИЯ requirements.txt ---
cat > requirements.txt <<EOF
aiogram==3.17.0
aiohttp==3.11.11
cryptography
EOF

# --- ГЕНЕРАЦИЯ Dockerfile ---
# Используем slim image для быстрой установки cryptography без компиляции
cat > Dockerfile <<EOF
FROM python:3.12-slim
WORKDIR /app
# Обновляем пакеты (на всякий случай)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY bot.py .
CMD ["python", "bot.py"]
EOF

# --- ГЕНЕРАЦИЯ docker-compose.yml ---
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

# --- ГЕНЕРАЦИЯ .env ---
cat > .env <<EOF
BOT_TOKEN=$BOT_TOKEN
XUI_URL=http://3x-ui:2053
XUI_USER=$USER
XUI_PASS=$PASS
EOF

# --- ГЕНЕРАЦИЯ bot.py ---
# ВАЖНО: Используем 'EOF' в кавычках, чтобы Bash не ломал Python-синтаксис
cat > bot.py << 'EOF'
import asyncio
import logging
import os
import json
import uuid
import aiohttp
import secrets
import base64
from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives import serialization
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import Command
from aiogram.types import InlineKeyboardMarkup, InlineKeyboardButton

# === КОНФИГУРАЦИЯ ===
TOKEN = os.getenv("BOT_TOKEN")
XUI_URL = os.getenv("XUI_URL")
XUI_USER = os.getenv("XUI_USER")
XUI_PASS = os.getenv("XUI_PASS")
VERSION = "1.1.0"

# Логирование
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

bot = Bot(token=TOKEN)
dp = Dispatcher()

def generate_keys():
    """Генерация ключей VLESS Reality (URL-Safe Base64)"""
    private_key = x25519.X25519PrivateKey.generate()
    public_key = private_key.public_key()
    
    # URL-safe base64 без паддинга
    priv_b64 = base64.urlsafe_b64encode(private_key.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption()
    )).decode('utf-8').rstrip('=')
    
    pub_b64 = base64.urlsafe_b64encode(public_key.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw
    )).decode('utf-8').rstrip('=')
    
    return priv_b64, pub_b64

async def create_full_inbound(session, base_url, client_email):
    """Создает новый Inbound 443 Reality, если его нет"""
    priv_key, pub_key = generate_keys()
    short_id = secrets.token_hex(4)
    new_uuid = str(uuid.uuid4())
    dest = "www.microsoft.com:443"
    sni = "www.microsoft.com"
    
    payload = {
        "up": 0, "down": 0, "total": 0, "remark": "Reality-443",
        "enable": True, "expiryTime": 0, "listen": "", 
        "port": 443, "protocol": "vless",
        "settings": json.dumps({
            "clients": [{
                "id": new_uuid, "flow": "xtls-rprx-vision", "email": client_email,
                "limitIp": 0, "totalGB": 0, "expiryTime": 0, "enable": True, "tgId": "", "subId": ""
            }],
            "decryption": "none", "fallbacks": []
        }),
        "streamSettings": json.dumps({
            "network": "tcp", "security": "reality",
            "realitySettings": {
                "show": False, "xver": 0, "dest": dest,
                "serverNames": [sni, "microsoft.com"],
                "privateKey": priv_key, "shortIds": [short_id],
                "settings": {"publicKey": pub_key, "fingerprint": "chrome", "serverName": "", "spiderX": "/"}
            },
            "tcpSettings": {"acceptProxyProtocol": False, "header": {"type": "none"}}
        }),
        "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"]})
    }

    async with session.post(f"{base_url}/panel/api/inbounds/add", json=payload) as resp:
        res = await resp.json()
        if not res.get("success"):
            return f"Error creating inbound: {res.get('msg')}"

    # Получаем IP
    try:
        async with session.get("http://checkip.amazonaws.com", timeout=2) as ip_resp:
            host_ip = (await ip_resp.text()).strip()
    except:
        host_ip = "YOUR_IP"

    link = (f"vless://{new_uuid}@{host_ip}:443?type=tcp&security=reality"
            f"&pbk={pub_key}&fp=chrome&sni={sni}&sid={short_id}"
            f"&spx=%2F&flow=xtls-rprx-vision#{client_email}")
    
    return link

async def get_3xui_link(tg_username: str) -> str:
    """Авторизация и создание клиента в 3x-ui"""
    if not tg_username:
        tg_username = f"user_{uuid.uuid4().hex[:8]}"
    
    base_url = XUI_URL.rstrip('/')
    client_email = f"{tg_username}_tg"

    async with aiohttp.ClientSession() as session:
        # 1. Логин
        login_payload = {"username": XUI_USER, "password": XUI_PASS}
        async with session.post(f"{base_url}/login", data=login_payload) as resp:
            if resp.status != 200:
                return "Error: Login failed (Check credentials)"
            if not (await resp.json()).get('success'):
                return "Error: Login success=false"

        # 2. Поиск Inbound
        async with session.get(f"{base_url}/panel/api/inbounds/list") as resp:
            data = await resp.json()
            inbounds = data.get("obj", [])
            
        target = next((i for i in inbounds if i["port"] == 443), None)
        
        if not target:
            return await create_full_inbound(session, base_url, client_email)

        # 3. Добавление клиента к существующему Inbound
        inbound_id = target["id"]
        stream_settings = json.loads(target["streamSettings"])
        
        try:
            public_key = stream_settings["realitySettings"]["settings"]["publicKey"]
            short_id = stream_settings["realitySettings"]["shortIds"][0]
            sni = stream_settings["realitySettings"]["serverNames"][0]
        except:
             return "Error: Reality keys not found/bad config"

        # Проверка дубликатов
        settings = json.loads(target["settings"])
        existing_client = next((c for c in settings["clients"] if c["email"] == client_email), None)
        
        if existing_client:
            new_uuid = existing_client["id"]
        else:
            new_uuid = str(uuid.uuid4())
            client_payload = {
                "id": inbound_id,
                "settings": json.dumps({
                    "clients": [{
                        "id": new_uuid, "flow": "xtls-rprx-vision", "email": client_email,
                        "limitIp": 0, "totalGB": 0, "expiryTime": 0, "enable": True, "tgId": "", "subId": ""
                    }]
                })
            }
            async with session.post(f"{base_url}/panel/api/inbounds/addClient", json=client_payload) as resp:
                if not (await resp.json()).get("success"):
                    return "Error adding client"

        # Получаем IP
        try:
            async with session.get("http://checkip.amazonaws.com") as ip_resp:
                host_ip = (await ip_resp.text()).strip()
        except:
            host_ip = "YOUR_IP"

        link = (f"vless://{new_uuid}@{host_ip}:443?type=tcp&security=reality"
                f"&pbk={public_key}&fp=chrome&sni={sni}&sid={short_id}"
                f"&spx=%2F&flow=xtls-rprx-vision#{client_email}")
        
        return link

@dp.message(Command("start"))
async def cmd_start(message: types.Message):
    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🚀 Получить VLESS ключ", callback_data="get_vpn")]
    ])
    text = (f"👋 <b>Привет, {message.from_user.first_name}!</b>\n\n"
            f"Нажми кнопку, чтобы создать личный ключ доступа.")
    await message.answer(text, reply_markup=kb, parse_mode="HTML")

@dp.callback_query(F.data == "get_vpn")
async def process_get_vpn(callback: types.CallbackQuery):
    await callback.message.edit_text("⏳ <b>Генерирую ключ...</b>", parse_mode="HTML")
    
    username = callback.from_user.username or f"id{callback.from_user.id}"
    link = await get_3xui_link(username)
    
    if "Error" in link:
        await callback.message.edit_text(f"❌ <b>Ошибка:</b>\n{link}", parse_mode="HTML")
    else:
        await callback.message.edit_text(
            f"✅ <b>Ваш ключ готов!</b>\n\n<code>{link}</code>\n\n"
            f"Нажмите на ключ для копирования.",
            parse_mode="HTML"
        )

async def main():
    await bot.delete_webhook(drop_pending_updates=True)
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
EOF

# 4. Запуск Docker
echo "🚀 Запуск контейнера..."
# На всякий случай останавливаем старый контейнер и чистим кэш сборки
docker-compose down 2>/dev/null
docker-compose up -d --build

echo ""
echo "=========================================="
echo "✅ БОТ УСТАНОВЛЕН И ЗАПУЩЕН!"
echo "Логи: docker logs -f tg-bot"
echo "=========================================="