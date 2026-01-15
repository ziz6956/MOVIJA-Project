#!/bin/bash

# curl -Ls "https://gist.githubusercontent.com/ziz6956/66bebbc204b89a0984ecfd0318b1179a/raw/add_modules.sh?v=$(date +%s)" | sudo bash
# add_modules.sh - Добавляет Test Mode без переписывания логики

GREEN='\033[0;32m'
NC='\033[0m'
WORK_DIR="/opt/tg-bot"
DATA_DIR="$WORK_DIR/data"
CONFIG_FILE="$DATA_DIR/config.json"
CLI_FILE="/usr/local/bin/tg-bot"

if [ ! -d "$WORK_DIR" ]; then
    echo "❌ Сначала установите бота!"
    exit 1
fi

echo -e "${GREEN}=== ДОБАВЛЕНИЕ МОДУЛЯ TEST-MODE ===${NC}"

# 1. Установка jq
if ! command -v jq &> /dev/null; then
    apt-get update && apt-get install -y jq
fi

# 2. Создание конфига
mkdir -p "$DATA_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
    echo '{"test_mode": false, "password": "admin"}' > "$CONFIG_FILE"
    chmod 666 "$CONFIG_FILE"
fi

# 3. Обновление docker-compose (Добавляем volume)
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

# 4. Обновление bot.py
# Мы берем твой код и вставляем IF-проверку прямо внутрь process_get_vpn
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
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.fsm.storage.memory import MemoryStorage

# === КОНФИГУРАЦИЯ ===
TOKEN = os.getenv("BOT_TOKEN")
XUI_URL = os.getenv("XUI_URL")
XUI_USER = os.getenv("XUI_USER")
XUI_PASS = os.getenv("XUI_PASS")
CONFIG_PATH = "/app/data/config.json"

logging.basicConfig(level=logging.INFO)
bot = Bot(token=TOKEN)
dp = Dispatcher(storage=MemoryStorage())

# === STATES & CONFIG UTILS ===
class Form(StatesGroup):
    waiting_for_password = State()

def get_config():
    try:
        with open(CONFIG_PATH, 'r') as f: return json.load(f)
    except: return {"test_mode": False, "password": "admin"}

# === ТВОИ СТАРЫЕ ФУНКЦИИ ГЕНЕРАЦИИ ===
def generate_keys():
    private_key = x25519.X25519PrivateKey.generate()
    public_key = private_key.public_key()
    priv_b64 = base64.urlsafe_b64encode(private_key.private_bytes(encoding=serialization.Encoding.Raw, format=serialization.PrivateFormat.Raw, encryption_algorithm=serialization.NoEncryption())).decode('utf-8').rstrip('=')
    pub_b64 = base64.urlsafe_b64encode(public_key.public_bytes(encoding=serialization.Encoding.Raw, format=serialization.PublicFormat.Raw)).decode('utf-8').rstrip('=')
    return priv_b64, pub_b64

async def create_full_inbound(session, base_url, client_email):
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
        if not res.get("success"): return f"Error creating inbound: {res.get('msg')}"
    try:
        async with session.get("http://checkip.amazonaws.com", timeout=2) as ip_resp: host_ip = (await ip_resp.text()).strip()
    except: host_ip = "YOUR_IP"
    link = (f"vless://{new_uuid}@{host_ip}:443?type=tcp&security=reality"
            f"&pbk={pub_key}&fp=chrome&sni={sni}&sid={short_id}"
            f"&spx=%2F&flow=xtls-rprx-vision#{client_email}")
    return link

async def get_3xui_link(tg_username: str) -> str:
    if not tg_username: tg_username = f"user_{uuid.uuid4().hex[:8]}"
    base_url = XUI_URL.rstrip('/')
    client_email = f"{tg_username}_tg"
    async with aiohttp.ClientSession() as session:
        login_payload = {"username": XUI_USER, "password": XUI_PASS}
        async with session.post(f"{base_url}/login", data=login_payload) as resp:
            if resp.status != 200: return "Error: Login failed (Check credentials)"
            if not (await resp.json()).get('success'): return "Error: Login success=false"
        async with session.get(f"{base_url}/panel/api/inbounds/list") as resp:
            data = await resp.json()
            inbounds = data.get("obj", [])
        target = next((i for i in inbounds if i["port"] == 443), None)
        if not target: return await create_full_inbound(session, base_url, client_email)
        inbound_id = target["id"]
        stream_settings = json.loads(target["streamSettings"])
        try:
            public_key = stream_settings["realitySettings"]["settings"]["publicKey"]
            short_id = stream_settings["realitySettings"]["shortIds"][0]
            sni = stream_settings["realitySettings"]["serverNames"][0]
        except: return "Error: Reality keys not found/bad config"
        settings = json.loads(target["settings"])
        existing_client = next((c for c in settings["clients"] if c["email"] == client_email), None)
        if existing_client: new_uuid = existing_client["id"]
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
                if not (await resp.json()).get("success"): return "Error adding client"
        try:
            async with session.get("http://checkip.amazonaws.com") as ip_resp: host_ip = (await ip_resp.text()).strip()
        except: host_ip = "YOUR_IP"
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

# === ВОТ ЗДЕСЬ ТВОЙ КОД С МАЛЕНЬКОЙ ВСТАВКОЙ В НАЧАЛЕ ===

@dp.callback_query(F.data == "get_vpn")
async def process_get_vpn(callback: types.CallbackQuery, state: FSMContext):
    # --- ВСТАВКА НАЧАЛО: Проверка режима ---
    cfg = get_config()
    if cfg.get("test_mode"):
        await callback.message.answer("🔒 <b>Режим закрытого тестирования.</b>\nВведите пароль:", parse_mode="HTML")
        await state.set_state(Form.waiting_for_password)
        await callback.answer() # Убираем часики с кнопки
        return # Прерываем функцию, ключ пока не даем
    # --- ВСТАВКА КОНЕЦ ---

    # ТВОЙ ОРИГИНАЛЬНЫЙ КОД НИЖЕ
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

# === ОБРАБОТЧИК ПАРОЛЯ (ДУБЛИРУЕМ ЛОГИКУ ВЫДАЧИ ТУТ) ===
@dp.message(Form.waiting_for_password)
async def process_password(message: types.Message, state: FSMContext):
    cfg = get_config()
    if message.text.strip() == cfg.get("password"):
        await message.answer("✅ Пароль верный.")
        await state.clear()
        
        # ТУТ ПОВТОРЯЕМ ТВОЮ ЛОГИКУ ВЫДАЧИ КЛЮЧА
        status_msg = await message.answer("⏳ <b>Генерирую ключ...</b>", parse_mode="HTML")
        username = message.from_user.username or f"id{message.from_user.id}"
        link = await get_3xui_link(username)
        
        if "Error" in link:
            await status_msg.edit_text(f"❌ <b>Ошибка:</b>\n{link}", parse_mode="HTML")
        else:
            await status_msg.edit_text(
                f"✅ <b>Ваш ключ готов!</b>\n\n<code>{link}</code>\n\n"
                f"Нажмите на ключ для копирования.",
                parse_mode="HTML"
            )
    else:
        await message.answer("❌ Неверный пароль. Попробуйте снова:")

async def main():
    await bot.delete_webhook(drop_pending_updates=True)
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
EOF

# 5. Создание CLI (tg-bot)
cat > "$CLI_FILE" << 'EOF'
#!/bin/bash
CONFIG_FILE="/opt/tg-bot/data/config.json"

if [ "$1" == "help" ] || [ -z "$1" ]; then
    echo "Управление ботом:"
    echo "  tg-bot test-mode enable    - Включить пароль"
    echo "  tg-bot test-mode disable   - Отключить пароль"
    echo "  tg-bot test-mode status    - Статус"
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
            ;;
    esac
fi
EOF
chmod +x "$CLI_FILE"

# 6. Рестарт
echo "🚀 Применяем изменения..."
docker-compose down
docker-compose up -d --build
echo "✅ Готово! Модуль добавлен."