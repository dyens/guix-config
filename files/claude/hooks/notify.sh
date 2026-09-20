#!/bin/sh
# Уведомление: Claude Code закончил ответ или упёрся в запрос разрешения.
#
# Вешается на события Stop и PermissionRequest в ~/.claude/settings.json,
# см. README, раздел «Уведомления Claude Code».
#
# На stdin приходит JSON одной строкой: hook_event_name, cwd, session_id,
# transcript_path и прочее. jq в профиле нет, поэтому две нужные строки
# достаём grep'ом — для верхнеуровневых полей этого достаточно.
#
# Выходим ВСЕГДА нулём: код 2 для Claude Code означает блокирующую
# ошибку, и уведомлялка не должна мешать работе.

set -u

input=$(cat)

# Первое вхождение поля верхнего уровня. Именно первое: у greedy .* в sed
# выиграло бы последнее, а в transcript'е имена полей могут повторяться.
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
    SessionEnd)        what="сессия закрыта" ;;
    "")                what="сигнал" ;;
    *)                 what="$event" ;;
esac

where=""
[ -n "$cwd" ] && where=" · $(basename "$cwd")"

# Звонок. tmux видит его как вывод панели: красит вкладку, пишет в
# статусбар «Bell in window N» (visual-bell both) и пробрасывает дальше,
# в локальный терминал за ssh — см. files/tmux.conf.
#
# Пишем в tty ПАНЕЛИ, а не в /dev/tty. Управляющего терминала у хука может
# не быть: его запускает сам Claude Code, и /dev/tty тогда не открывается.
# А TMUX_PANE в окружении есть всегда, когда мы внутри tmux. Проверено на
# t1: запись \a в #{pane_tty} поднимает window_bell_flag, через /dev/tty
# до клиента не доезжало ни байта.
#
# Не в stdout: его читает сам Claude Code.
bell_to=""
if [ -n "${TMUX_PANE:-}" ]; then
    bell_to=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}' 2>/dev/null)
elif [ -n "${TMUX:-}" ]; then
    bell_to=$(tmux display-message -p '#{pane_tty}' 2>/dev/null)
fi
[ -n "$bell_to" ] || bell_to=/dev/tty

# Редирект обёрнут в группу: если цели нет, ругается САМ shell, и его
# stderr глушится снаружи — «printf ... 2>/dev/null» это не ловит.
{ printf '\a' > "$bell_to"; } 2>/dev/null

# Строка в статусбаре — она и несёт смысл. Штатное «Bell in window N»
# от visual-bell сообщает только факт, а не что именно случилось.
# ## — экранирование: одиночную # display-message примет за формат.
if [ -n "${TMUX:-}" ]; then
    msg=$(printf 'claude: %s%s' "$what" "$where" | sed 's/#/##/g')
    tmux display-message -d 5000 -- "$msg" 2>/dev/null
fi

exit 0
