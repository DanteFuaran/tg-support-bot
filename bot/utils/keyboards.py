from aiogram.types import ReplyKeyboardMarkup, KeyboardButton


def get_user_keyboard() -> ReplyKeyboardMarkup:
    """
    Основная клавиатура пользователя.
    Всегда отображается, не скрывается после нажатия.
    """
    buttons = [
        [
            KeyboardButton(text="✅ Вопрос успешно решён"),
            KeyboardButton(text="❌ Вопрос не был решён"),
            KeyboardButton(text="🧹 Очистить чат"),
        ]
    ]

    keyboard = ReplyKeyboardMarkup(
        keyboard=buttons,
        resize_keyboard=True,         # адаптируется под экран
        one_time_keyboard=False,      # клавиатура остаётся на месте
    )

    return keyboard