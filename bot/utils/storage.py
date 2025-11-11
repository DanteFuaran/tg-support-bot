import json
import time
import os
import logging
from bot.config import STORAGE_FILE, INACTIVITY_DAYS


class MemoryStorage:
    """
    Простое persistent-хранилище для данных бота поддержки.
    """

    def __init__(self):
        self.user_topics: dict[str, int] = {}
        self.g2u: dict[int, int] = {}  # group message -> user message
        self.u2g: dict[int, int] = {}  # user message -> group message
        self.last_activity: dict[int, float] = {}
        self.loaded = False
        self.load()

    # -------- Управление темами --------
    def set_topic(self, user_id: str, topic_id: int):
        self.user_topics[user_id] = topic_id
        self.update_activity(topic_id)

    def get_topic(self, user_id: str) -> int | None:
        return self.user_topics.get(user_id)

    def remove_topic(self, user_id: str):
        tid = self.user_topics.pop(user_id, None)
        if tid:
            self.last_activity.pop(tid, None)
            self._cleanup_message_links(tid)

    def find_user_by_topic(self, topic_id: int) -> str | None:
        for uid, tid in self.user_topics.items():
            if tid == topic_id:
                return uid
        return None

    # -------- Активность тем --------
    def update_activity(self, topic_id: int):
        self.last_activity[topic_id] = time.time()

    def get_last_activity(self, topic_id: int) -> float | None:
        return self.last_activity.get(topic_id)

    # -------- Связи сообщений --------
    def link_messages(self, group_msg_id: int, user_msg_id: int):
        self.g2u[group_msg_id] = user_msg_id
        self.u2g[user_msg_id] = group_msg_id

    def link_group_message(self, group_msg_id: int, user_msg_id: int):
        self.link_messages(group_msg_id, user_msg_id)

    def link_user_message(self, user_msg_id: int, group_msg_id: int):
        self.link_messages(group_msg_id, user_msg_id)

    def get_user_msg_by_group_msg(self, group_msg_id: int) -> int | None:
        return self.g2u.get(group_msg_id)

    def get_group_msg_by_user_msg(self, user_msg_id: int) -> int | None:
        return self.u2g.get(user_msg_id)

    # -------- Очистка старых данных --------
    def _cleanup_message_links(self, topic_id: int):
        """Очищает связи сообщений для указанной темы."""
        # Находим все сообщения, связанные с этой темой
        messages_to_remove = []
        for group_msg_id, user_msg_id in self.g2u.items():
            # Если сообщение принадлежит удаляемой теме, добавляем в список на удаление
            if self._is_message_from_topic(group_msg_id, topic_id):
                messages_to_remove.append((group_msg_id, user_msg_id))

        # Удаляем найденные связи
        for group_msg_id, user_msg_id in messages_to_remove:
            self.g2u.pop(group_msg_id, None)
            self.u2g.pop(user_msg_id, None)

    def _is_message_from_topic(self, message_id: int, topic_id: int) -> bool:
        """Проверяет, принадлежит ли сообщение указанной теме."""
        # Простая эвристика: если message_id находится в диапазоне topic_id ± 1000
        return abs(message_id - topic_id) < 1000

    def cleanup_old_data(self):
        """Очищает устаревшие данные при загрузке."""
        current_time = time.time()
        max_age = INACTIVITY_DAYS * 24 * 60 * 60  # Используем настройку из config

        # Очищаем last_activity от очень старых записей (более 7 дней)
        week_ago = current_time - (7 * 24 * 60 * 60)
        self.last_activity = {tid: ts for tid, ts in self.last_activity.items() 
                             if ts > week_ago or tid in self.user_topics.values()}

        # Очищаем связи сообщений от старых тем (более 3 дней)
        three_days_ago = current_time - max_age
        
        # Создаем новые словари только с актуальными данными
        new_g2u = {}
        new_u2g = {}
        
        for gid, uid in self.g2u.items():
            if self._get_message_timestamp(gid) > three_days_ago:
                new_g2u[gid] = uid
                
        for uid, gid in self.u2g.items():
            if self._get_message_timestamp(uid) > three_days_ago:
                new_u2g[uid] = gid

        # Логируем результат очистки
        removed_g2u = len(self.g2u) - len(new_g2u)
        removed_u2g = len(self.u2g) - len(new_u2g)
        
        if removed_g2u > 0 or removed_u2g > 0:
            logging.info(f"🧹 Очистка storage: удалено {removed_g2u} g2u и {removed_u2g} u2g записей")

        # Заменяем старые данные новыми
        self.g2u = new_g2u
        self.u2g = new_u2g

    def _get_message_timestamp(self, message_id: int) -> float:
        """Примерная временная метка сообщения на основе его ID."""
        try:
            # Базовое время (можно настроить под вашу дату начала проекта)
            base_time = 1700000000  # Пример: 14 ноября 2023
            return base_time + (int(message_id) / 1000)  # Преобразуем в int для безопасности
        except (ValueError, TypeError):
            # Если message_id некорректный, возвращаем текущее время
            return time.time()

    # -------- Сохранение / загрузка --------
    def save(self):
        """Сохраняет данные в JSON-файл с резервной копией."""
        try:
            data = {
                "user_topics": self.user_topics,
                "g2u": self.g2u,
                "u2g": self.u2g,
                "last_activity": self.last_activity,
            }

            # Создание резервной копии
            if os.path.exists(STORAGE_FILE):
                os.replace(STORAGE_FILE, STORAGE_FILE + ".bak")

            with open(STORAGE_FILE, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)

        except Exception as e:
            logging.error(f"⚠️ Ошибка сохранения {STORAGE_FILE}: {e}")

    def load(self):
        """Загружает данные из JSON-файла."""
        if not os.path.exists(STORAGE_FILE):
            logging.warning(f"📁 Файл хранилища не найден — будет создан: {STORAGE_FILE}")
            self.save()
            return

        try:
            with open(STORAGE_FILE, "r", encoding="utf-8") as f:
                raw = f.read().strip()
                if not raw:
                    raise ValueError("Файл пуст")

                data = json.loads(raw)

            self.user_topics = data.get("user_topics", {})
            self.g2u = data.get("g2u", {})
            self.u2g = data.get("u2g", {})
            self.last_activity = data.get("last_activity", {})
            self.loaded = True

            # Очищаем старые данные при загрузке
            self.cleanup_old_data()

        except Exception as e:
            logging.error(f"⚠️ Ошибка загрузки {STORAGE_FILE}: {e}")
            self.save()


storage = MemoryStorage()