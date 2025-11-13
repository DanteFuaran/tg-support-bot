#!/bin/bash
# version: 0.3.3

set -e
exec < /dev/tty

# Цвета
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

# Очистка при неудачной установке
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

# Безопасный ввод
safe_read() {
  local prompt="$1"
  local varname="$2"
  echo -ne "$prompt"
  IFS= read -r "$varname" || { echo; cleanup_on_fail; }
}

# Спиннер прогресса установки
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

# Красивый вывод
print_action() { printf "${BLUE}➜${NC}  %b\n" "$1"; }
print_error()  { printf "${RED}✖ %b${NC}\n" "$1"; }

# Заголовок установки
clear
echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}   🚀 УСТАНОВКА TELEGRAM SUPPORT BOT${NC}"
echo -e "${BLUE}==========================================${NC}\n"


# === Проверка лицензионного ключа ===
echo -e "Для продолжения установки введите лицензионный ключ"
echo -e "Если хотите прервать установку — нажмите Ctrl + C"
echo

# URL файла с хешами ключей
KEYS_URL="https://raw.githubusercontent.com/DanteFuaran/tg-support-bot/master/license"

# Функция проверки ключа
validate_license_key() {
    local input_key="$1"
    local key_hash
    
    # Генерируем SHA256 хеш от введенного ключа
    key_hash=$(echo -n "$input_key" | sha256sum | awk '{print $1}')
    
    # Получаем все хеши и проверяем наличие
    local remote_hashes
    remote_hashes=$(curl -fsSL "$KEYS_URL" | tr -d '\r' | sed 's/[[:space:]]*$//')
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Ошибка: Не удалось загрузить файл ключей${NC}"
        return 1
    fi
    
    # Проверяем наличие хеша в списке
    if echo "$remote_hashes" | grep -q "^$key_hash$"; then
        return 0
    else
        return 1
    fi
}



touch "$LOCK_FILE"

if [ "$EUID" -ne 0 ]; then
  print_error "Запустите скрипт с правами root: sudo bash install.sh"
  exit 1
fi


# Обновление системы
export DEBIAN_FRONTEND=noninteractive

apt-get update -y >/dev/null 2>&1 &
show_spinner "Обновление списка пакетов"

apt-get upgrade -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  >/dev/null 2>&1 &
show_spinner "Обновление установленных пакетов"

# Обновление зависимостей
DEPENDENCIES=("python3" "python3-pip" "python3-venv" "git" "curl" "wget")

for pkg in "${DEPENDENCIES[@]}"; do
  if dpkg -s "$pkg" &>/dev/null; then
    print_action "$pkg уже установлен"
  else
    apt install -y "$pkg" >/dev/null 2>&1 &
    show_spinner "Установка $pkg"
  fi
done

echo -e "${GREEN}✅${NC} Проверка установленных пакетов\n"

# Подготовка каталога
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


# Создание Python .venv
python3 -m venv .venv >/dev/null 2>&1 &
show_spinner "Создание виртуального окружения"

source .venv/bin/activate
pip install -r requirements.txt >/dev/null 2>&1 &
show_spinner "Установка зависимостей Python"
deactivate

echo -e "${GREEN}✅${NC} Все зависимости установлены\n"


# Создание конфиг файлов
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

# Инициализация базы данных
(
  if [ -f "$INSTALL_DIR/storage.json" ]; then
    :
  elif [ -f "$INSTALL_DIR/storage.example.json" ]; then
    cp "$INSTALL_DIR/storage.example.json" "$INSTALL_DIR/storage.json"
  else
    cat > "$INSTALL_DIR/storage.json" << 'JSON'
{
  "user_topics": {},
  "g2u": {},
  "u2g": {},
  "last_activity": {}
}
JSON
  fi
) &
show_spinner "Инициализация базы данных"


# Настройка автозагрузки бота
(
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
) &
show_spinner "Настройка автозапуска"


# Настройка .env
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

(sleep 0.2) &
show_spinner "Создание конфигурации"

# Создание панели управления
cat > "$CLI_FILE" << 'EOF'
#!/bin/bash
SERVICE="tg-support-bot.service"
INSTALL_DIR="/dfc-online/tg-support-bot"
ENV_FILE="$INSTALL_DIR/.env"

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
NC='\033[0m'
DARKGRAY='\033[1;30m'
YELLOW='\033[1;33m'

get_env() { grep "^$1=" "$ENV_FILE" | cut -d'=' -f2; }

show_menu() {
  clear
  echo -e "${BLUE}==============================${NC}"
  echo -e "${GREEN}      МЕНЮ БОТА ПОДДЕРЖКИ${NC}"
  echo -e "${BLUE}==============================${NC}"
  echo -e "${DARKGRAY}Текущие настройки${NC}"
  echo -e "🔑 Токен:        ${YELLOW}$(get_env BOT_TOKEN)${NC}"
  echo -e "🆔 ID группы:    ${YELLOW}$(get_env SUPPORT_GROUP_ID)${NC}"
  echo -e "⏱️  Автозакрытие: ${YELLOW}$(get_env INACTIVITY_DAYS) дней${NC}"
  echo -e "${DARKGRAY}------------------------------${NC}"
  echo -e "${DARKGRAY}Управление${NC}"
  echo -e "1.  Запустить бота"
  echo -e "2.  Перезапустить бота"
  echo -e "3.  Остановить бота"
  echo -e "4.  Просмотр логов"
  echo -e "${DARKGRAY}------------------------------${NC}"
  echo -e "${DARKGRAY}Изменить настройки${NC}"
  echo -e "5.  Изменить токен бота"
  echo -e "6.  Изменить ID группы"
  echo -e "7.  Изменить дни автозакрытия"
  echo -e "${DARKGRAY}------------------------------${NC}"
  echo -e "${DARKGRAY}Глобально${NC}"
  echo -e "8.  Переустановить бота"
  echo -e "9.  Удалить бота"
  echo -e "${DARKGRAY}------------------------------${NC}"
  echo -e "0.  Выход"
  echo -e "${BLUE}==============================${NC}"
}

edit_env() {
  local key="$1"
  local label="$2"
  local confirm_message=""

  case "$key" in
    BOT_TOKEN)
      confirm_message="${RED}⚠ Вы уверены, что хотите изменить токен бота? (y/N): ${NC}"
      ;;
    SUPPORT_GROUP_ID)
      confirm_message="${RED}⚠ Вы уверены, что хотите изменить ID группы? (y/N): ${NC}"
      ;;
    INACTIVITY_DAYS)
      confirm_message="${RED}⚠ Вы уверены, что хотите изменить количество дней до автозакрытия тикета? (y/N): ${NC}"
      ;;
    *)
      confirm_message="${RED}⚠ Вы уверены, что хотите изменить ${label}? (y/N): ${NC}"
      ;;
  esac

  read -p "Введите новое значение для ${label}: " value

  if [ -z "$value" ]; then
    echo -e "${YELLOW}⚠ Изменение отменено: значение не введено.${NC}"
    sleep 2
    return
  fi

  read -p "$(echo -e "$confirm_message")" confirm
  case "$confirm" in
    [yY][eE][sS]|[yY])
      sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
      echo -e "${GREEN}✅ Значение ${label} обновлено.${NC}"
      ;;
    *)
      echo -e "${YELLOW}❌ Изменение ${label} отменено пользователем.${NC}"
      sleep 2
      ;;
  esac
}

delete_bot_files() {
  echo -e "\n${RED}⚠ Полное удаление бота и всех файлов...${NC}"
  systemctl stop "$SERVICE" 2>/dev/null || true
  systemctl disable "$SERVICE" 2>/dev/null || true
  rm -rf "$INSTALL_DIR" /etc/systemd/system/"$SERVICE"
  systemctl daemon-reload
  echo -e "${GREEN}✅ Удаление завершено.${NC}\n"
}

delete_bot() {
  read -p "$(echo -e "${RED}⚠ Вы уверены, что хотите полностью удалить бота и все файлы? (y/N): ${NC}")" confirm
  case "$confirm" in
    [yY][eE][sS]|[yY])
      delete_bot_files
      rm -f "$0"
      exit 0
      ;;
    *)
      echo -e "${YELLOW}❌ Удаление отменено пользователем.${NC}"
      sleep 2
      ;;
  esac
}

reinstall_bot() {
  read -p "$(echo -e "${RED}⚠ Вы уверены, что хотите переустановить бота (удаление + новая установка)? (y/N): ${NC}")" confirm
  case "$confirm" in
    [yY][eE][sS]|[yY])
      echo -e "${BLUE}🔁 Выполняется переустановка...${NC}"
      delete_bot_files
      echo -e "${BLUE}⬇️  Загрузка и установка новой версии...${NC}"
      bash <(curl -s "https://raw.githubusercontent.com/DanteFuaran/tg-support-bot/master/install.sh")
      exit 0
      ;;
    *)
      echo -e "${YELLOW}❌ Переустановка отменена пользователем.${NC}"
      sleep 2
      ;;
  esac
}

while true; do
  show_menu
  read -p "Выберите действие: " c
  case $c in
    1) systemctl start $SERVICE && echo -e "${GREEN}✅ Бот запущен${NC}"; sleep 2;;
    2) systemctl restart $SERVICE && echo -e "${GREEN}🔁 Перезапущен${NC}"; sleep 2;;
    3) systemctl stop $SERVICE && echo -e "${RED}⛔ Остановлен${NC}"; sleep 2;;
    4) journalctl -u $SERVICE -n 50 --no-pager; read -p "Нажмите Enter...";;
    5) edit_env "BOT_TOKEN" "токен бота";;
    6) edit_env "SUPPORT_GROUP_ID" "ID группы";;
    7) edit_env "INACTIVITY_DAYS" "дней автозакрытия";;
    8) reinstall_bot;;
    9) delete_bot;;
    0) echo -e "${GREEN}👋 Выход из панели.${NC}"; echo; exit 0;;
    *) echo -e "${RED}⚠ Неверный выбор${NC}"; sleep 1;;
  esac
done
EOF

(sleep 0.2) &
show_spinner "Создание панели управления"

chmod +x "$CLI_FILE"


# Запуск бота
sleep 1
systemctl daemon-reload >/dev/null 2>&1
systemctl enable tg-support-bot.service >/dev/null 2>&1
systemctl restart tg-support-bot.service >/dev/null 2>&1
sleep 1

if systemctl is-active --quiet tg-support-bot.service; then
  echo -e "${GREEN}✅${WHITE} Бот успешно запущен!${NC}"
else
  echo -e "${RED}❌ Не удалось запустить бота автоматически.${NC}"
  echo -e "${YELLOW}Попробуйте вручную: systemctl start tg-support-bot.service${NC}"
fi


# Очистка мусора
find "$INSTALL_DIR" -type d -name "__pycache__" -exec rm -rf {} + >/dev/null 2>&1
find "$INSTALL_DIR" -type f -name "*.pyc" -delete >/dev/null 2>&1
rm -f "$LOCK_FILE" /tmp/pip-* /tmp/tmp.*

rm -rf "$INSTALL_DIR/.git"
rm -f "$INSTALL_DIR/.gitignore" \
      "$INSTALL_DIR/.gitattributes" \
      "$INSTALL_DIR/.env.example" \
      "$INSTALL_DIR/README.md" \
      "$INSTALL_DIR/LICENSE" \
      "$INSTALL_DIR/requirements.txt" \
      "$INSTALL_DIR/install.sh" \
      "$INSTALL_DIR/storage.example.json"

# Готово!
echo -e "\n${BLUE}==========================================${NC}"
echo -e "${GREEN}    🎉 УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО! ${NC}"
echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}Меню управления ботом:${NC} ${YELLOW}tg-support-bot${NC}\n"
