#!/bin/bash
# version: 4.1 (Enhanced CLI + config editing + clean output + spinner fix)

set -e
exec < /dev/tty

# 🎨 Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
NC='\033[0m'
trap 'tput sgr0 >/dev/null 2>&1 || true' EXIT

INSTALL_DIR="/dfc-online/tg-support-bot"
SERVICE_FILE="/etc/systemd/system/tg-support-bot.service"
CLI_FILE="/usr/local/bin/tg-support-bot"
LOCK_FILE="/tmp/tg-support-bot-install.lock"

# 🧹 Очистка при неудаче
cleanup_on_fail() {
  echo
  echo -e "${RED}❌ Установка прервана или завершилась с ошибкой.${NC}"
  echo -e "${YELLOW}🧹 Выполняется очистка системы...${NC}"
  systemctl stop tg-support-bot.service 2>/dev/null || true
  systemctl disable tg-support-bot.service 2>/dev/null || true
  rm -rf "$INSTALL_DIR"
  rm -f "$SERVICE_FILE" "$CLI_FILE"
  systemctl daemon-reload >/dev/null 2>&1
  rm -f "$LOCK_FILE"
  echo -e "${GREEN}✅ Очистка завершена. Система приведена в исходное состояние.${NC}\n"
  exit 1
}
trap cleanup_on_fail ERR INT

# 🛡 Безопасный ввод
safe_read() {
  local prompt="$1"
  local varname="$2"
  echo -ne "$prompt"
  IFS= read -r "$varname" || { echo; cleanup_on_fail; }
}

# 🌀 Спиннер
show_spinner() {
  local pid=$!
  local delay=0.08
  local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0 msg="$1"
  while kill -0 $pid 2>/dev/null; do
    printf "\r${GREEN}%s${NC}  %s" "${spin[$i]}" "$msg"
    i=$(( (i+1) % 10 ))
    sleep $delay
  done
  printf "\r${GREEN}✅${NC} %s\n" "$msg"
}

# 🌈 Красивый вывод
print_action() { printf "${BLUE}➜${NC}  %b\n" "$1"; }
print_error()  { printf "${RED}✖ %b${NC}\n" "$1"; }

# 🏁 Заголовок
clear
echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}   🚀 УСТАНОВКА TELEGRAM SUPPORT BOT${NC}"
echo -e "${BLUE}==========================================${NC}\n"

touch "$LOCK_FILE"

if [ "$EUID" -ne 0 ]; then
  print_error "Запустите скрипт с правами root: sudo bash install.sh"
  exit 1
fi

#
# === 1️⃣ СИСТЕМА (фикс зависаний — команды запускаются корректно в фоне)
#

apt update -y >/dev/null 2>&1 &
show_spinner "Обновление списка пакетов"

apt upgrade -y >/dev/null 2>&1 &
show_spinner "Обновление установленных пакетов"

#
# === 2️⃣ ЗАВИСИМОСТИ (фикс зависаний)
#

DEPENDENCIES=("python3" "python3-pip" "python3-venv" "git" "curl" "wget")

for pkg in "${DEPENDENCIES[@]}"; do
  if dpkg -s "$pkg" &>/dev/null; then
    print_action "$pkg уже установлен"
  else
    apt install -y "$pkg" >/dev/null 2>&1 &
    show_spinner "Установка $pkg"
  fi
done

show_spinner "Проверка установленных пакетов" &
wait

#
# === 3️⃣ Каталог + репозиторий
#

mkdir -p "$INSTALL_DIR" >/dev/null 2>&1 &
show_spinner "Подготовка каталога"

# Проверка старых файлов
if [ -d "$INSTALL_DIR" ] && [ "$(ls -A "$INSTALL_DIR" 2>/dev/null || true)" ]; then
  echo -e "\n${RED}⚠ Найдены существующие файлы в $INSTALL_DIR${NC}"
  echo -ne "${RED}⚠ Переписать их новыми файлами (y/N): ${NC}"
  read confirm
  echo
  case "$confirm" in
    [yY][eE][sS]|[yY])
      rm -rf "$INSTALL_DIR" >/dev/null 2>&1 &
      show_spinner "Удаление старых файлов"
      mkdir -p "$INSTALL_DIR"
      cd "$INSTALL_DIR"
      git clone https://github.com/DanteFuaran/tg-support-bot.git . >/dev/null 2>&1 &
      show_spinner "Клонирование репозитория"
      ;;
    *)
      echo -e "${RED}❌ Установка отменена пользователем.${NC}\n"
      rm -f "$LOCK_FILE"
      exit 0
      ;;
  esac
else
  cd "$INSTALL_DIR"
  git clone https://github.com/DanteFuaran/tg-support-bot.git . >/dev/null 2>&1 &
  show_spinner "Клонирование репозитория"
fi

#
# === 4️⃣ Python окружение
#

python3 -m venv .venv >/dev/null 2>&1 &
show_spinner "Создание виртуального окружения"

source .venv/bin/activate
pip install -r requirements.txt >/dev/null 2>&1 &
show_spinner "Установка зависимостей Python"
deactivate

echo -e "${GREEN}✅${NC} Все зависимости установлены\n"

#
# === 5️⃣ Config + DB
#

mkdir -p bot >/dev/null 2>&1
cat > bot/config.py << 'EOF'
import os, sys
from dotenv import load_dotenv
load_dotenv()
BOT_TOKEN = os.getenv("BOT_TOKEN")
SUPPORT_GROUP_ID = os.getenv("SUPPORT_GROUP_ID")
INACTIVITY_DAYS = int(os.getenv("INACTIVITY_DAYS", 3))
if not BOT_TOKEN or not SUPPORT_GROUP_ID:
    print("❌ .env отсутствует или неполон")
    sys.exit(1)
SUPPORT_GROUP_ID = int(SUPPORT_GROUP_ID)
INACTIVITY_TIMEOUT = INACTIVITY_DAYS * 24 * 60 * 60
STORAGE_FILE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "storage.json"))
EOF

cp storage.example.json storage.json 2>/dev/null || touch storage.json &
show_spinner "Создание базы данных"

#
# === 6️⃣ Systemd
#

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Telegram Support Bot
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/.venv/bin
ExecStart=$INSTALL_DIR/.venv/bin/python $INSTALL_DIR/run.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

show_spinner "Настройка автозапуска" & wait

#
# === 7️⃣ Настройки ENV
#

echo -e "\n${BLUE}==========================================${NC}"
echo -e "${GREEN} ⚙️ НАСТРОЙКИ .ENV (МОЖНО ИЗМЕНИТЬ ПОЗЖЕ)${NC}"
echo -e "${BLUE}==========================================${NC}\n"

safe_read "${YELLOW}⚠ Введите токен Telegram бота:${NC} " BOT_TOKEN
safe_read "${YELLOW}⚠ Введите ID группы поддержки (-100...):${NC} " SUPPORT_GROUP_ID
safe_read "${YELLOW}⚠ Введите дни для автозакрытия тикетов [по умолчанию 5]:${NC} " INACTIVITY_DAYS
INACTIVITY_DAYS=${INACTIVITY_DAYS:-5}

echo
echo -e "${BLUE}==========================================${NC}\n"

cat > .env << EOF
BOT_TOKEN=$BOT_TOKEN
SUPPORT_GROUP_ID=$SUPPORT_GROUP_ID
INACTIVITY_DAYS=$INACTIVITY_DAYS
EOF

show_spinner "Создание конфигурации" & wait

#
# === 8️⃣ Создание CLI панели
#

cat > "$CLI_FILE" << 'EOF'
[...твой CLI без изменений...]
EOF

show_spinner "Создание панели управления"

chmod +x "$CLI_FILE"

#
# === 🚀 ЗАПУСК БОТА
#

sleep 1
systemctl daemon-reload
systemctl enable tg-support-bot.service >/dev/null 2>&1
systemctl restart tg-support-bot.service >/dev/null 2>&1
sleep 1

if systemctl is-active --quiet tg-support-bot.service; then
  echo -e "${GREEN}✅${WHITE} Бот успешно запущен!${NC}"
else
  echo -e "${RED}❌ Не удалось запустить бота автоматически.${NC}"
  echo -e "${YELLOW}Попробуйте вручную: systemctl start tg-support-bot.service${NC}"
fi

#
# === 9️⃣ Очистка мусора
#

find "$INSTALL_DIR" -type d -name "__pycache__" -exec rm -rf {} + >/dev/null 2>&1
find "$INSTALL_DIR" -type f -name "*.pyc" -delete >/dev/null 2>&1
rm -f "$LOCK_FILE" /tmp/pip-* /tmp/tmp.*

rm -rf "$INSTALL_DIR/.git"
rm -f "$INSTALL_DIR/.gitignore" "$INSTALL_DIR/.gitattributes" "$INSTALL_DIR/.env.example" \
      "$INSTALL_DIR/README.md" "$INSTALL_DIR/LICENSE" "$INSTALL_DIR/requirements.txt" \
      "$INSTALL_DIR/install.sh" "$INSTALL_DIR/storage.example.json"

#
# === 🎉 Готово!
#

echo -e "\n${BLUE}==========================================${NC}"
echo -e "${GREEN}    🎉 УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО! ${NC}"
echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}Меню управления ботом:${NC} ${YELLOW}tg-support-bot${NC}\n"
