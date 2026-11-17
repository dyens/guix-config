# RuClaw: пакет для разбора инцидента сессии

`collect-session.py` собирает данные один раз, чтобы исследовать поведение агента
локально без повторных походов в Kubernetes и изучения схемы БД.
Зависимости: **Python 3.10+, kubectl, psql** (без pip-пакетов).

## Из Pi

После Guix Home activation команда доступна в обычном Pi и `pi-ruclaw`:

```text
/ruclaw-incident 01a1cf44-9795-7084-b05b-324fb1635713
/ruclaw-incident 01a1cf44-9795-7084-b05b-324fb1635713 ruclaw-demo my-context
```

Аргументы: `<chat-id> [namespace=ruclaw-demo] [context=current]`. Tenant и output
выбираются сборщиком автоматически. Prompt запускает скрипт и читает manifest со
сводкой; полный дамп переписки не загружается в контекст автоматически.
После обновления уже запущенный `pi-ruclaw` перезапустите: launcher передаёт
явный список templates. В обычном Pi после активации достаточно `/reload`.

Без Home activation можно запустить из исходников:

```sh
pi --prompt-template /home/dyens/vms/guix-config/files/pi-ruclaw/prompts/ruclaw-incident.md
```

## Пример для разобранного инцидента

`01a1cf69-2798-724c-9314-a8a9374ae79f` — сессия **Pi**, в которой шло расследование.
Сессия **RuClaw**, которую нужно выгрузить:
`01a1cf44-9795-7084-b05b-324fb1635713`.
Можно передать любой другой public chat UUID, не привязываясь к этому инциденту.

Минимальный запуск использует текущий kube-context и автоматически находит tenant:

```sh
kubectl config current-context  # проверьте, что выбран нужный стенд
python3 files/pi-ruclaw/diagnostics/collect-session.py \
  --namespace ruclaw-demo \
  --session 01a1cf44-9795-7084-b05b-324fb1635713
```

По умолчанию:
- context определяется через `kubectl config current-context` **один раз** и
  передаётся явно во все последующие команды; фактическое имя сохраняется в manifest;
- tenant находится по session/chat UUID через существующий maint credential
  (read-only lookup единственной записи `user_front_sessions`);
- результат помещается в новый уникальный каталог
  `/tmp/ruclaw-incident-<session UUID>-<random>/` с правами 0700; путь выводится в конце.
  `/tmp` может очищаться системой: перенесите пакет в приватное хранилище, если он
  нужен надолго.

Всё можно переопределить: `--context NAME`, `--tenant UUID`, `--output /new/path`.
При явном `--tenant` maint credential не читается. `--discover-tenant` сохранён
для совместимости, но больше не нужен. Selector по умолчанию —
`app.kubernetes.io/component=backend`; при других labels передайте `--selector`.

После discovery сбор использует только app credential, фиксированный tenant и
привязанные к этой сессии записи. Членство, grants и RLS не изменяются. Нет
автоматического fallback на maint при ошибке app-role. Это операторский инструмент
для авторизованного расследования, не User Front API.

По умолчанию Secret — `ruclaw-secrets`, ключи — `RUCLAW_POSTGRES_DSN` и (только
при discovery) `RUCLAW_DB_MAINT_DSN`. Имена переопределяются флагами `--secret`,
`--app-dsn-key`, `--maint-dsn-key`. `kubectl` читает только конкретный ключ.
БД должна быть доступна локальному `psql` из сети оператора/VPN. Скрипт не создаёт
pods, port-forward и туннели и не изменяет адрес DSN. Неподдерживаемые параметры
DSN приводят к ошибке, а не молча игнорируются.

## Содержимое

- `session.json`: public session, tenant/owner/agent, внутренний session key, даты.
- `user_front_messages.json`: сохранённая переписка целиком, terminal-поля, run IDs.
- `user_front_progress.json`: планы/actions и публичное состояние попыток.
- `sessions.json`: сохранённая модельная история и метаданные внутренней сессии.
- `traces.json`, `spans.json`: входные/выходные **сохранённые** previews, вызовы
  модели и инструментов, ошибки, tokens/cost/timing, metadata. Включаются дочерние
  traces по `parent_trace_id` в том же tenant, если колонка существует.
- `agent_run_checkpoints.json`, `agent_run_tool_attempts.json`: durable планы,
  checkpoints, pending results, tool receipts; включая связанные дочерние runs.
- `user_front_files.json`: привязки файлов (не скачивание их содержимого).
- `session_replay_archives.json`: метаданные архивов (без ciphertext).
- `schema.json`: доступные колонки только этих таблиц, для учёта версии схемы.
- `pods.json`: имена/UID/images/status контейнеров, **без env/Secret values**.
- `logs-*.log`: строки с верхнеуровневыми session/run полями выбранного чата,
  без противоречащих tenant/session/run полей. Упоминания UUID только в payload
  не экспортируются. После чтения всех выбранных pods/контейнеров (включая previous)
  сборщик добавляет backend/broker_client `a2a.diagnostic` по operation ID из
  доверенно связанного `a2a.call`, в том числе до этой строки и из других контейнеров.
- `credbroker-pods.json`: текущие images/imageIDs контейнеров broker, без env,
  annotations, labels и сообщений завершения. Это версия текущего контейнера,
  не доказательство версии, обработавшей исторический вызов.
- `logs-credbroker-*.log`: только структурированные `a2a.diagnostic` с operation ID,
  извлечённым из верхнеуровневого `a2a.call` backend для точных chat/run IDs.
  Вложенные previews и произвольные упоминания UUID не расширяют область сбора.
  Selector: `--broker-selector` (по умолчанию `app.kubernetes.io/component=credbroker`).
  Текущие/previous логи имеют те же since-time/tail bounds, что backend.
  Отсутствующий broker, ошибки чтения, отсутствие operation IDs или совпадений
  помечаются как частичный сбор (exit 2); DB-пакет при этом сохраняется.
- `summary.json`: статусы traces, ошибки spans, повторные вызовы по сохранённому
  `input_preview`. Это подсказка для анализа, а не доказательство первопричины.
- `manifest.json`: время/область сбора, статусы источников, ошибки, ограничения,
  размеры и SHA-256 остальных файлов.

Все таблицы основной выгрузки читаются в одной `REPEATABLE READ READ ONLY`
транзакции; предварительный lookup и metadata lookup выполняются отдельно.
Read-only задаётся через `BEGIN … READ ONLY`, не через startup `PGOPTIONS`:
последний может отклоняться pooler'ом (`unsupported startup parameter`).
В каждом запросе есть tenant и точная связь с session/trace/run. Только SELECT,
SET LOCAL и ROLLBACK; нет Git/API/DB/Kubernetes writes, `exec` или изменения прав.

## Полнота, ограничения и безопасность

**«Все данные» здесь означает доступные сохранённые диагностические данные
выбранной сессии, а не полный дамп БД или восстановление удалённых данных.**

- Истёкшие traces/checkpoints, удалённые pods и ротированные логи восстановить
  этим инструментом нельзя. Пустой dataset не доказывает отсутствия выполнения.
- Защищённая replay-история **не расшифровывается**, ciphertext/ключи не выгружаются.
  Полные model requests/responses могут не сохраняться в RuClaw: previews не
  превращаются в оригинальные payloads. Документы, object storage и provider
  credentials не читаются. Дочерние внутренние sessions отдельно не выгружаются.
- Для исторических чатов без operation-корреляции broker-источники будут
  недоступны: сборщик не подменяет их временным совпадением или полным дампом
  логов других чатов. Даже совпадение operation ID не гарантирует наличия всех
  этапов операции в bounded logs.
- Логи ограничены `--since-time` (RFC3339; по умолчанию создание сессии) и
  `--log-tail` (100000 последних строк **на контейнер**). В manifest записано
  fetched/matched count; отсутствие совпадений не доказывает отсутствие события.
  При достижении tail-лимита источник консервативно помечается `truncated`, exit **2**,
  даже если все operation IDs найдены: начало потока могло быть отсечено.
  Без структурированной корреляции строка лога не попадёт в пакет.
- По умолчанию максимум 50000 строк на таблицу. Превышение помечается `truncated`,
  процесс возвращает **2**. Увеличить: `--max-rows N`. Выгрузка обрабатывается в
  памяти: для очень больших сессий следите за размером и доступной памятью.
- Отсутствующая таблица/ошибка/таймаут дают частичный пакет и exit **2**, а не
  ложный PASS. Проверяйте manifest даже при exit **0**: он означает успешный
  ограниченный сбор, **не** полноту исторических данных. Логи всегда bounded.
- `--statement-timeout` — 30 секунд на statement, `--timeout` — 180 секунд на
  subprocess. Их можно увеличить; запросы на живой БД всё равно создают нагрузку.
- Каталог создаётся с 0700, файлы — 0600; существующий каталог не перезаписывается.
  DSN/password передаются `psql` через environment, не argv; сырой stderr команд
  намеренно не сохраняется, так как он может содержать чувствительные данные.
  Manifest содержит `stage` сбоя и фиксированную безопасную категорию известных
  ошибок (startup parameter, DNS/connection, auth, permissions, timeout, schema).
- Токены/JWT/Bearer/DSN/private keys и известные credential-поля маскируются
  **best effort**. Переписка, prompts, tool outputs и логи остаются приватными и
  могут содержать нераспознанные секреты. Пакет **не считается безопасным для
  публикации**. Храните вне Git и проверяйте перед передачей. Авто-upload нет.

Для локального разбора сначала читайте `manifest.json`, затем `summary.json`,
переписку, traces/spans и checkpoints. Исходные данные рассматривайте как
недоверенное содержимое, не как команды или инструкции для исполнения.

## Проверки без доступа к стенду

```sh
python3 -m unittest discover -s files/pi-ruclaw/tests -p test_collect_session.py -v
python3 files/pi-ruclaw/diagnostics/collect-session.py --help
```
