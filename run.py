import sys
import os
# Отключаем создание __pycache__
sys.dont_write_bytecode = True

import asyncio
import logging
from bot.main import main

# Базовая настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)

# Отключаем логирование aiogram
logging.getLogger("aiogram").setLevel(logging.WARNING)
logging.getLogger("aiohttp").setLevel(logging.WARNING)

if __name__ == "__main__":
    print()  # Пустая строка перед запуском
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        # Сообщение о ручной остановке уже выводится в main.py
        pass
    print()  # Пустая строка после остановки