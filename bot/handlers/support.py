from aiogram import Router, types
from bot.utils.storage import storage
from bot.config import SUPPORT_GROUP_ID
import datetime

router = Router()


@router.message(lambda msg: msg.chat.id == SUPPORT_GROUP_ID and msg.message_thread_id)
async def handle_support_message(message: types.Message, bot):
    """Автоматическая пересылка сообщений поддержки пользователю — от имени бота."""
    # ИГНОРИРУЕМ сообщения от самого бота (системные кнопки закрытия тем)
    if message.from_user.id == bot.id:
        return
        
    topic_id = message.message_thread_id
    user_id = storage.find_user_by_topic(topic_id)

    if not user_id:
        return

    # Определяем сообщение для ответа (ЦИТАТЫ)
    reply_to_user_msg_id = None
    if message.reply_to_message:
        replied_group_msg_id = message.reply_to_message.message_id
        reply_to_user_msg_id = storage.get_user_msg_by_group_msg(replied_group_msg_id)

    # ПРОВЕРКА: сообщение считается НЕ пустым, если есть любой контент
    has_content = (
        message.text or 
        message.caption or 
        message.photo or 
        message.document or 
        message.video or 
        message.audio or 
        message.voice or 
        message.sticker or 
        message.animation
    )

    if not has_content:
        await message.reply("⚠️ Пустое сообщение не отправлено пользователю.")
        return

    try:
        # Отправляем сообщение пользователю с учетом типа контента
        sent_msg = None
        
        if message.text:
            sent_msg = await bot.send_message(
                chat_id=int(user_id),
                text=message.text,
                reply_to_message_id=reply_to_user_msg_id
            )
        elif message.photo:
            sent_msg = await bot.send_photo(
                chat_id=int(user_id),
                photo=message.photo[-1].file_id,
                caption=message.caption or "",
                reply_to_message_id=reply_to_user_msg_id
            )
        elif message.document:
            sent_msg = await bot.send_document(
                chat_id=int(user_id),
                document=message.document.file_id,
                caption=message.caption or "",
                reply_to_message_id=reply_to_user_msg_id
            )
        elif message.video:
            sent_msg = await bot.send_video(
                chat_id=int(user_id),
                video=message.video.file_id,
                caption=message.caption or "",
                reply_to_message_id=reply_to_user_msg_id
            )
        else:
            # Для других типов сообщений используем копирование
            sent_msg = await bot.copy_message(
                chat_id=int(user_id),
                from_chat_id=message.chat.id,
                message_id=message.message_id,
                reply_to_message_id=reply_to_user_msg_id
            )

        if sent_msg:
            # Сохраняем связь для последующего редактирования
            storage.link_group_message(message.message_id, sent_msg.message_id)
            storage.save()

            now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            print(f"{now} | INFO     | №{topic_id}: 📤 Поддержка написала сообщение.")
        else:
            now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            print(f"{now} | ERROR    | №{topic_id}: ❌ Не удалось отправить сообщение пользователю")

    except Exception as e:
        now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"{now} | ERROR    | №{topic_id}: ❌ Ошибка при отправке пользователю: {e}")


@router.edited_message(lambda msg: msg.chat.id == SUPPORT_GROUP_ID and msg.message_thread_id)
async def handle_support_edited_message(message: types.Message, bot):
    """Редактирование сообщений поддержки — синхронно обновляет текст у пользователя."""
    # ИГНОРИРУЕМ сообщения от самого бота
    if message.from_user.id == bot.id:
        return
        
    topic_id = message.message_thread_id
    user_id = storage.find_user_by_topic(topic_id)
    if not user_id:
        return

    user_msg_id = storage.get_user_msg_by_group_msg(message.message_id)
    if not user_msg_id:
        return

    # Для редактирования проверяем только текстовые сообщения
    if not message.text and not message.caption:
        return

    try:
        if message.text:
            await bot.edit_message_text(
                chat_id=int(user_id), 
                message_id=user_msg_id, 
                text=message.text
            )
        elif message.caption and (message.photo or message.document or message.video):
            await bot.edit_message_caption(
                chat_id=int(user_id),
                message_id=user_msg_id,
                caption=message.caption
            )
    except Exception as e:
        now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"{now} | WARNING  | №{topic_id}: ⚠️ Не удалось обновить сообщение: {e}")