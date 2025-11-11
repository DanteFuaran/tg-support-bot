import os
import sys
from dotenv import load_dotenv

# Загрузка переменных окружения
load_dotenv()

BOT_TOKEN = os.getenv("BOT_TOKEN")
SUPPORT_GROUP_ID = os.getenv("SUPPORT_GROUP_ID")
INACTIVITY_DAYS = int(os.getenv("INACTIVITY_DAYS", 3))

# Проверка обязательных параметров
if not BOT_TOKEN:
    print("❌ Ошибка: BOT_TOKEN не найден в .env")
    sys.exit(1)

if not SUPPORT_GROUP_ID:
    print("❌ Ошибка: SUPPORT_GROUP_ID не найден в .env")
    sys.exit(1)

SUPPORT_GROUP_ID = int(SUPPORT_GROUP_ID)

# Системные настройки
INACTIVITY_TIMEOUT = INACTIVITY_DAYS * 24 * 60 * 60

# Абсолютный путь до хранилища
STORAGE_FILE = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "storage.json")
)