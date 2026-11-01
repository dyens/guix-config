# Pi для RuClaw — plan-cycle v2 по умолчанию

Личный профиль для `~/dev/croc/ruclaw`. Обычный `pi`, командные файлы проекта,
credentials и модели не меняются. Новых зависимостей нет.

## Запуск

После `homerec`, в новом shell:

```sh
pi-ruclaw
pi-ruclaw --check
pi-ruclaw --session <v2-session-id>
pi-ruclaw-runner .scratch/RCL-821 --only 08,09   # внутри tmux
```

Без активации Home:

```sh
python3 ~/vms/guix-config/files/pi-ruclaw/launch.py --check
python3 ~/vms/guix-config/files/pi-ruclaw/launch.py
```

Для обычного запроса на реализацию workflow v2 выбирается профилем автоматически.
Явный вход в Pi также доступен:

```text
/skill:implement .scratch/RCL-XXX/issues/NN-task.md
```

Launcher подключает shared `plan-cycle` v2 и native pi-subagents. В исходниках
расширение берётся из `files/pi-extensions/plan-cycle/`, после Home activation — из
`~/.config/pi-plan-cycle/`. Это не глобальный autoload для обычного Pi.
`--check` показывает workflow и пути, но не вызывает модель и не проверяет продукт.

## Новый базовый процесс

```text
Прочитать задачу/полномочия и нужные исходные файлы
  → plan_cycle_start: checkpoint 0
  → короткий plan.md
  → plan_cycle_next
  → TODO → INPROGRESS → DONE → следующий шаг
  → целевые регрессии + дешёвый CI-preflight → разрешённый commit
  → финальный fresh review || тяжёлые проверки того же кандидата
  → findings становятся новым планом исправлений
  → согласованные publication/status/cleanup gates
```

Код пишет основной Pi. Нет implementation workers, старых phase manifests,
обязательного interim review каждого increment или `ruclaw_next_cycle`.

**Разрешения по умолчанию для implement:** обычные локальные коммиты собственных
изменений задачи на согласованной task-ветке и Docker/Compose для изолированных
ресурсов задачи (build/pull, запуск/остановка/удаление своих контейнеров и сетей).
Агент записывает эти полномочия в план и не спрашивает заново перед review/каждым fix.
Явные ограничения конкретной задачи важнее defaults. Это не разрешение на push/MR,
смену ветки, merge/rebase/переписывание истории, коммиты в develop/main/release,
shared/prod, global prune, удаление volumes/persistent-данных или privileged/security
bypass. Для них нужны отдельные полномочия. Reviewer/ops остаются в своих узких ролях.

- План короткий: шаги, ключевые решения, исходный base/branch/scope, краткие итоги,
  changed/created/deleted пути и ссылки на детали. Статусы только TODO / INPROGRESS /
  DONE / BLOCKED. DONE шага не означает приёмку всей задачи.
- Исправления/review/integration той же задачи продолжают её цикл. Новая отдельная
  задача после согласованного endpoint — свежая сессия с handoff и собственным base,
  а не продолжение старого плана через новые ветки. Старый writer должен быть idle,
  children завершены, открытые gates и полномочия сохранены со ссылками на источники.
  `stop/start` не очищает контекст: stop возвращает обычную историю.
- До INPROGRESS перечитываются нужные изменённые/созданные файлы. Задача уже в
  checkpoint: её не перечитывают ритуально после каждого перехода.
- План и инвалидизация чтений checkpoint фиксируются **на границе шага** и
  сохраняются в session entries. Внутри шага prefix не переписывается: новые
  read/edit/write results дополняют хвост, показывая более свежие версии.
- Возврат касается контекста, не файлов/Git. Переписка остаётся в transcript.
  Новые пользовательские инструкции сохраняются дословно между шагами; завершённые
  `ask_user_question` сохраняются как исходные пары вызов/результат. Отмена/ошибка или
  пропущенный вопрос не означают согласие, последующие поправки имеют приоритет.
- BLOCKED/INPROGRESS запрещают next. При ошибке плана агент сохраняет причину и
  перепланирует в текущем контексте; scope/permissions сам не расширяет.
- Промежуточный код может не работать, если это явно записано. Финальный кандидат
  требует необходимых проверок и независимого review. До review — применимые дешёвые
  CI-проверки, включая security lint для Go-тестов и версии инструментов из CI.
  Review и тяжёлые проверки можно выполнять параллельно на неизменяемом кандидате
  при изолированных ресурсах; до исправлений/перехода все запуски завершаются.
  Детали проверок и их перенос/инвалидизация — в связанном индексе, не в журнале плана.
  Отдельный запуск нового integration-теста на чистом backend проверяет автономность
  fixture. Повторный дефект одного инварианта требует пересмотра контракта, не цепочки
  точечных патчей.
- Основной reviewer — `ruclaw-plan-reviewer`: fresh, report-only, без наследования
  project/global/skills. Полномочия/точные refs/task/evidence передаются явно.
  Follow-up смотрит delta + affected invariants, без обязательного полного rereview.
- Необязательный `ruclaw-ops` помогает с разрешёнными изолированными проверками.
  Children не делегируют дальше; перед переходом нужно завершить всех children.
- Publication только по реальным полномочиям. Runner сохраняет прежний согласованный
  non-force push gate; локальный source-only endpoint не подменяет task done или
  production acceptance. Required skipped/blocked checks остаются незакрытыми.

Ручные команды `/plan-cycle start <path>`, `next`, `status`, `stop` тоже доступны;
при обычном `/skill:implement` checkpoint создаёт агент через `plan_cycle_start`.
Compaction в активном режиме отменяется: слишком большой шаг надо разделить или
сохранить handoff, а не надеяться на пересказ checkpoint. Старые цитаты/bash/search
output автоматически не обновляются. Это не sandbox и не доказательство честности
плана/проверок. [Полный контракт расширения](../pi-extensions/plan-cycle/README.md).

## Контекст и файлы

- Автозагрузка team AGENTS/CLAUDE, skills и prompt templates выключена.
  `/wait-what [тема]` подключён явно: объясняет предыдущий ответ или указанную тему
  простыми словами, без продолжения реализации. Шаблон — `prompts/wait-what.md`;
  он также устанавливается для обычного Pi через Guix Home.
- Личные инструкции, `profile/project.md` и короткий `profile/workflow.md`
  подключаются явно; areas/testing читаются выборочно. Launcher передаёт в system
  prompt их абсолютные пути и отдельно путь product checkout: профиль лежит вне
  репозитория, `areas.md`/`testing.md` нельзя искать в его корне. `read` не раскрывает
  переменные окружения. Описания не объявляют старую документацию безусловной истиной.
- `skills/implement/SKILL.md` — default workflow;
  `references/plan-cycle.md` — safeguards; `result-contract.md` — short/detail reports.
- `agents/plan-reviewer.md` — default reviewer. `ruclaw-reviewer` сохранён для
  отдельного code-review skill/legacy; это не обязательный второй pass default.
- `PI_RUCLAW_ROOT`, `PI_RUCLAW_GLOBALS`, `PI_SUBAGENT_EXTRA_AGENT_DIRS` передают
  пути профиля/личных инструкций/ролей; не печатай весь env.
- Детали/логи — в отдельных результатах. Отчёт child неизменяемый, parent dispositions
  отдельно; `output:false/outputMode:inline`, никаких single-file receipt overrides.

## Ретроспектива процесса: `/skill:retro`

```text
/skill:retro
/skill:retro /absolute/path/to/session.jsonl
/skill:retro <session-id> — фокус на review, проверках и расходе контекста
```

Без аргументов анализирует текущую переписку; по пути/ID — указанную сессию.
Скилл восстанавливает эпизоды и ищет улучшения implement/review, проверок, инструментов
и управления контекстом. Сравнивает исторический runtime с текущими инструкциями,
разделяет необходимые проверки и лишние повторы, предлагает приоритетные изменения
с доказательствами и способом проверить пользу. Не меняет файлы/процесс автоматически:
внедрение — по отдельному запросу. Неполная история и недоступные child/CI evidence
остаются ограничениями, а не поводом домысливать результаты или получать доступ.

`skills/retro/scripts/session-summary.py <session.jsonl>` строит локальную сводку без
моделей и новых зависимостей: структурные счётчики, usage, размеры plan snapshots,
повторы чтений и ссылки на строки. Не печатает тексты сообщений, аргументы инструментов
или пути из лога; идентификаторы путей хешируются. Это подсчёт serialized entries всех
веток, не реального model context и не всех расходов дочерних агентов. Секреты из
точечных выдержек тоже нужно скрывать до вывода. Старые логи не редактируются.

Исходник: `skills/retro/SKILL.md`; идеи [upstream retro](https://github.com/mattpocock/skills/tree/main/skills/engineering/retro)
адаптированы под Pi/RuClaw. Устанавливается вместе с профилем через `homerec`, новые
Ponytail runtimes тоже включают скилл; запуск не требует изменения product checkout.

## Существующие сессии и legacy

Активные процессы сами не переключаются после изменения файлов/`homerec`.
Для новой конфигурации нужен новый запуск; `/reload` не заменяет launch flags.

Старый work-cycles оставлен только для явного восстановления:

```sh
pi-ruclaw --legacy-cycles --session <old-session-id>
pi-ruclaw --legacy-cycles --check
```

В этом режиме используется старое extension и `implement/references/resume.md`,
а не новый implement onboarding. Default v2 обнаруживает сохранённую legacy boundary
и выдаёт STOP вместо молчаливого смешивания процессов. Старые manifests/transcripts
и frozen runtimes пилотов сохраняются. Для plan-cycle v1 также нет тихой миграции.

Для перехода старой задачи в новую сессию: сначала сделать прежнего писателя idle,
сохранить handoff (original bases/HEAD/dirty ownership, открытые gates, ресурсы,
решения/следующий шаг), затем явно восстановить задачу в v2. Не делать reset/stash/
clean и не объявлять done ради переключения. Ctrl-C runner не останавливает Pi.

[Ponytail full](ponytail/README.md) — отдельный opt-in вариант: те же plan-cycle v2
и полномочия, но upstream Ponytail вместо наших code-design/review инструкций.
Default и существующие сессии не переключаются.

[Lite](lab/README.md) остаётся отдельным opt-in экспериментом; alias не менялся.
[Runner](runner/README.md) запускает свежий default v2 Pi на каждую задачу, ждёт
runner_finish и не является владельцем приёмки.

## Проверки без моделей

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s files/pi-ruclaw/tests -p 'test_*.py'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s files/pi-ruclaw/runner/tests -p 'test_*.py'
node files/pi-ruclaw/tests/runtime-smoke.mjs
node --import ./files/pi-ruclaw/tests/peers.mjs --test files/pi-extensions/tests/plan-cycle.test.ts files/pi-ruclaw/tests/work-cycles.test.mjs
python3 files/pi-ruclaw/launch.py --check
```

Тесты используют временные repos и native Pi loaders, не вызывают модели. Они
проверяют wiring/контекст/legacy separation, не качество реализации продуктовых задач.
