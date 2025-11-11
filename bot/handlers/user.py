from aiogram import Router, types
from bot.utils.senders import forward_message
from bot.utils.keyboards import get_user_keyboard
from bot.handlers.helpers import create_user_topic, close_topic_system
from bot.config import SUPPORT_GROUP_ID
import asyncio
import datetime

router = Router()


@router.message(lambda msg: msg.chat.type == "private")
async def user_message_handler(message: types.Message, bot, **data):
    """Обработка всех личных сообщений от пользователя."""
    storage = data["storage"]
    user_id = str(message.from_user.id)
    user_name = message.from_user.first_name or "Пользователь"
    username = f"@{message.from_user.username}" if message.from_user.username else "нет username"

    # Очистка чата
    if message.text == "🧹 Очистить чат":
        topic_id = storage.get_topic(user_id)

        if topic_id:
            await message.answer(
                "⚠️ Нельзя очистить чат пока решается ваш вопрос.\n"
                "Сначала закройте вопрос с помощью кнопок ниже 👇",
                reply_markup=get_user_keyboard(),
            )
            return

        try:
            await message.answer("Если будут новые вопросы - просто напишите мне.")
            await asyncio.sleep(0.3)

            for msg_id in range(message.message_id, message.message_id - 250, -1):
                try:
                    await bot.delete_message(message.chat.id, msg_id)
                    await asyncio.sleep(0.005)
                except Exception:
                    pass
        except Exception as e:
            print(f"⚠️ Ошибка при очистке чата: {e}")
        return

    # Закрытие темы
    if message.text in ("✅ Вопрос успешно решён", "❌ Вопрос не был решён"):
        topic_id = storage.get_topic(user_id)

        if not topic_id:
            await message.answer("ℹ️ У вас нет открытых вопросов.", reply_markup=get_user_keyboard())
            return

        is_success = "успешно" in message.text

        # Логируем закрытие темы
        current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"{current_time} | INFO     | №{topic_id}: ✅ Вопрос успешно решён." if is_success else f"{current_time} | INFO     | №{topic_id}: ❌ Вопрос не был решён.")

        try:
            await close_topic_system(
                bot,
                topic_id=topic_id,
                user_id=int(user_id),
                closed_by="user",
                close_type=("success" if is_success else "unsuccess"),
            )
        except Exception as e:
            print(f"⚠️ Ошибка close_topic_system: {e}")

        await message.answer(
            "Если будут новые вопросы - просто напишите мне."
            if is_success else
            "❌ Мне искренне жаль, что я не смог вам помочь.\nЕсли будут новые вопросы - просто напишите мне.",
            reply_markup=get_user_keyboard(),
        )
        return

    # Проверка / создание темы
    topic_id = storage.get_topic(user_id)
    is_new_topic = False

    if not topic_id:
        topic_id = await create_user_topic(bot, user_id, user_name, username)
        storage.set_topic(user_id, topic_id)
        is_new_topic = True
        current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"{current_time} | INFO     | №{topic_id}: ✅ Пользователь {user_id} открыл тему.")

    # Пересылка в группу
    sent_group_msg_id = await forward_message(
        bot,
        SUPPORT_GROUP_ID,
        message,
        thread_id=topic_id,
    )

    if sent_group_msg_id:
        storage.link_user_message(message.message_id, sent_group_msg_id)
        storage.update_activity(topic_id)
        current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"{current_time} | INFO     | №{topic_id}: 📩 {user_id} написал сообщение.")

    # Подтверждение для нового тикета
    if is_new_topic:
        await message.answer(
            "<b>Ваше сообщение отправлено в поддержку.</b>\nПожалуйста, ожидайте ответа...",
            reply_markup=get_user_keyboard(),
        )


@router.edited_message(lambda msg: msg.chat.type == "private")
async def user_edited_message_handler(message: types.Message, bot, **data):
    """Обработка ОТРЕДАКТИРОВАННЫХ сообщений от пользователя."""
    storage = data["storage"]
    user_id = str(message.from_user.id)
    
    topic_id = storage.get_topic(user_id)
    if not topic_id:
        return

    # Ищем соответствующее сообщение в группе
    group_msg_id = storage.get_group_msg_by_user_msg(message.message_id)
    
    if not group_msg_id:
        return

    try:
        # Редактируем сообщение в группе
        if message.text:
            await bot.edit_message_text(
                chat_id=SUPPORT_GROUP_ID,
                message_id=group_msg_id,
                text=message.text
            )
        elif message.caption and (message.photo or message.document or message.video):
            # Для медиа-сообщений с подписью
            await bot.edit_message_caption(
                chat_id=SUPPORT_GROUP_ID,
                message_id=group_msg_id,
                caption=message.caption
            )
        
        # УБРАНО: лишнее логирование редактирования
        
    except Exception as e:
        current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        error_msg = str(e)
        if "message can't be edited" in error_msg:
            print(f"{current_time} | WARNING  | №{topic_id}: ⚠️ Сообщение нельзя отредактировать (возможно, прошло более 48 часов)")
        elif "message to edit not found" in error_msg:
            print(f"{current_time} | WARNING  | №{topic_id}: ⚠️ Сообщение для редактирования не найдено")
        else:
            print(f"{current_time} | WARNING  | №{topic_id}: ⚠️ Не удалось отредактировать сообщение в группе: {e}")