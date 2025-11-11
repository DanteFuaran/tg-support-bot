from aiogram import Bot, types
from bot.utils.keyboards import get_user_keyboard
from bot.utils.storage import storage

# УДАЛИТЬ эту строку - она вызывает циклический импорт
# from bot.utils.senders import forward_message


async def forward_message(
    bot: Bot,
    target_id: int,
    message: types.Message,
    *,
    thread_id: int | None = None,
    reply_to: int | None = None,
    to_user: bool = False,
) -> int | None:
    """
    Универсальная пересылка сообщений с поддержкой цитат.
    """
    kwargs = {"chat_id": target_id}
    if thread_id:
        kwargs["message_thread_id"] = thread_id
    if to_user:
        kwargs["reply_markup"] = get_user_keyboard()

    try:
        # Определяем ID сообщения для ответа
        reply_to_id = reply_to
        if not reply_to_id and message.reply_to_message:
            replied_id = message.reply_to_message.message_id
            if to_user:
                reply_to_id = storage.get_user_msg_by_group_msg(replied_id)
            else:
                reply_to_id = storage.get_group_msg_by_user_msg(replied_id)

        if reply_to_id:
            kwargs["reply_to_message_id"] = reply_to_id

        # Отправка сообщения
        sent = None
        if message.text:
            sent = await bot.send_message(**kwargs, text=message.text)
        elif message.photo:
            sent = await bot.send_photo(**kwargs, photo=message.photo[-1].file_id, caption=message.caption or "")
        elif message.document:
            sent = await bot.send_document(**kwargs, document=message.document.file_id, caption=message.caption or "")
        elif message.video:
            sent = await bot.send_video(**kwargs, video=message.video.file_id, caption=message.caption or "")
        else:
            copy_kwargs = kwargs.copy()
            copy_kwargs.update({
                "from_chat_id": message.chat.id,
                "message_id": message.message_id
            })
            sent = await bot.copy_message(**copy_kwargs)

        if not sent:
            return None

        # Сохраняем связи сообщений (БЕЗ DEBUG ЛОГОВ)
        if to_user:
            storage.link_group_message(message.message_id, sent.message_id)
        else:
            storage.link_user_message(message.message_id, sent.message_id)

        return sent.message_id

    except Exception as e:
        print(f"⚠️ Ошибка при пересылке сообщения: {e}")
        return None