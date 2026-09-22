#!/bin/sh
# Уведомление в Telegram: Claude Code закончил ответ или ждёт разрешения.
#
# Вешается на события Stop и PermissionRequest в files/claude/settings.json.
# На stdin приходит JSON одной строкой; jq в профиле нет, поэтому нужные
# поля достаём grep'ом.
#
# ЧЕРЕЗ SOCKS. С t1 api.telegram.org недоступен — соединение отваливается
# по таймауту (проверено: другие хосты открываются, этот нет). Поэтому
# идём через SOCKS Xray-клиента из home/xray.scm, 127.0.0.1:10808. Через
# него Telegram отвечает нормально. Следствие: если сервис xray лежит,
# уведомлений не будет — смотреть `herd status xray`.
#
# Выходим ВСЕГДА нулём: код 2 для Claude Code означает блокирующую ошибку,
# и уведомлялка не должна мешать работе.
#
# Всё, что не получилось, пишется в лог — чтобы «уведомления пропали»
# диагностировалось за пять секунд, а не гаданием.

set -u

SECRET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/secrets/telegram.env"
SOCKS="127.0.0.1:10808"
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/claude-notify.log"

log() {
    mkdir -p "$(dirname "$LOG")" 2>/dev/null
    printf '%s %s\n' "$(date -Iseconds 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null
}

input=$(cat)

# Первое вхождение поля верхнего уровня.
field() {
    printf '%s' "$input" \
        | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
        | head -1 \
        | sed 's/.*:[[:space:]]*"//; s/"$//'
}

event=$(field hook_event_name)
cwd=$(field cwd)

case "$event" in
    PermissionRequest) what="ждёт разрешения" ;;
    Stop)              what="готов" ;;
    StopFailure)       what="не закончил" ;;
    "")                what="сигнал" ;;
    *)                 what="$event" ;;
esac

where=""
[ -n "$cwd" ] && where=" · $(basename "$cwd")"

if [ ! -r "$SECRET" ]; then
    log "нет $SECRET — секрет не расшифрован? herd restart home-sops-secrets"
    exit 0
fi

# shellcheck disable=SC1090
. "$SECRET"
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    log "в $SECRET нет TELEGRAM_BOT_TOKEN или TELEGRAM_CHAT_ID"
    exit 0
fi

text="$(hostname) · claude ${what}${where}"

out=$(curl -sS --max-time 10 --socks5-hostname "$SOCKS" \
          --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
          --data-urlencode "text=${text}" \
          "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" 2>&1)

case "$out" in
    *'"ok":true'*) ;;
    *)
        # Токен из сообщения об ошибке вычищаем: лог не должен его содержать.
        log "не отправилось: $(printf '%s' "$out" \
              | sed "s|${TELEGRAM_BOT_TOKEN}|<TOKEN>|g" | head -c 200)"
        ;;
esac

exit 0
