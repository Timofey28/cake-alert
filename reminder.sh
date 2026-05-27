#!/bin/bash

# Проверяем, существует ли файл, и загружаем его
ENV_FILE="$(dirname "$0")/.env"
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo "Ошибка: файл .env не найден!" >&2
    exit 1
fi

# Функция отправки сообщения в Telegram
send_telegram_message() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=Markdown"
}

# Функция получения правильного окончания слова в зависимости от числа
pluralize() {
    local number="$1"
    local form1="$2"
    local form2="$3"
    local form5="$4"
    local n100=$(( number % 100 ))
    local n10=$(( number % 10 ))
    if (( n100 >= 11 && n100 <= 19 )); then
        echo "$number $form5"
    elif (( n10 == 1 )); then
        echo "$number $form1"
    elif (( n10 >= 2 && n10 <= 4 )); then
        echo "$number $form2"
    else
        echo "$number $form5"
    fi
}

# Получаем текущую дату и даты на N недель вперёд
TODAY=$(date +"%d.%m")
CURRENT_YEAR=$(date +"%Y")

# Максимальное количество недель для напоминания
MAX_WEEKS=8

# Создаем ассоциативный массив для хранения напоминаний
declare -A reminders

# Инициализируем массивы для каждого возможного периода
for (( i=0; i<=$MAX_WEEKS; i++ )); do
    reminders["$i"]=""
done

# Чтение файла построчно
while IFS= read -r line || [[ -n "$line" ]]; do
    # Пропускаем пустые строки и комментарии
    line_cleaned=$(echo "$line" | sed 's/#.*//' | xargs)
    if [[ -z "$line_cleaned" ]]; then
        continue
    fi

    # Разбираем строку: *-флаги, дата, имя (может содержать пробелы)
    stars=$(echo "$line_cleaned" | grep -o '^\**' | tr -cd '*' | wc -c)
    bdate_part=$(echo "$line_cleaned" | sed -E 's/^(\**)[[:space:]]*//' | awk '{print $1}')
    name=$(echo "$line_cleaned" | sed -E 's/^(\**)[[:space:]]*//' | sed -E "s/^[^[:space:]]+[[:space:]]+//")

    # Если дата пустая, пропускаем
    if [[ -z "$bdate_part" ]]; then
        continue
    fi

    # Проверяем, есть ли год
    if [[ "$bdate_part" =~ \.[0-9]{4}$ ]]; then
        birth_year=$(echo "$bdate_part" | awk -F '.' '{print $3}')
        age=$(pluralize $(( CURRENT_YEAR - birth_year )) "год" "года" "лет")
        age_text=" ($age)"
        bdate_no_year=$(echo "$bdate_part" | sed 's/\.[0-9]\{4\}$//')
    else
        age_text=""
        bdate_no_year="$bdate_part"
    fi

    # Проверяем все возможные периоды (сегодня, +1 неделя, +2 недели и т.д.)
    for (( i=0; i<=$MAX_WEEKS; i++ )); do
        target_date=$(date -d "+$i weeks" +"%d.%m")
        if [[ "$bdate_no_year" == "$target_date" ]]; then
            # Если звёздочек достаточно для этого периода или это сам день рождения (i=0)
            if [[ $i -le $stars || $i -eq 0 ]]; then
                reminder="- ${name}${age_text}"
                reminders["$i"]="${reminders[$i]}${reminder}"$'\n'
            fi
        fi
    done
done < "$BIRTHDAYS_FILE"

# Формируем финальное сообщение
FINAL_MESSAGE="*📅 Дни рождения:*"$'\n\n'

for (( i=0; i<=$MAX_WEEKS; i++ )); do
    if [[ -n "${reminders[$i]}" ]]; then
        if [[ $i -eq 0 ]]; then
            FINAL_MESSAGE+="*🎉Сегодня:*"$'\n'"${reminders[$i]}"$'\n'
        else
            weeks=$(pluralize $i "неделю" "недели" "недель")
            FINAL_MESSAGE+="*⏳ Через $weeks*:"$'\n'"${reminders[$i]}"$'\n'
        fi
    fi
done

# Отправляем сообщение, если есть напоминания
if [[ "$FINAL_MESSAGE" != "*📅 Дни рождения:*"$'\n\n' ]]; then
    #FINAL_MESSAGE+="Не забудь всех поздравить! 🎁"
    send_telegram_message "$FINAL_MESSAGE"
fi
