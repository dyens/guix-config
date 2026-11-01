# Аудит RuClaw для личного Pi-профиля

## Цель и договорённости

Получить компактное, проверенное описание текущего RuClaw для
`profile/project.md` и карту навигации для `profile/areas.md`, заменяющие массовую
загрузку репозиторных CLAUDE/AGENTS. Не создавать ещё одну спецификацию системы.

- `project.md` описывает систему, её компоненты и важные ограничения, а не порядок
  работы агента. Runner, review, exact-SHA, handoff, children туда не входят.
- Git/changelog conventions остаются явной ссылкой с указанием читать перед
  соответствующими операциями. Актуальность самой ссылки ещё проверить.
- ADR, specs, README и инструкции не считаются актуальными только из-за имени,
  расположения или статуса. Сопоставлять их с реализацией и уточнениями пользователя.
- Код показывает фактическое поведение, но не превращает баг в требование.
- `sources.json` и блокировка запуска по хешам командных документов удалены
  после согласования профиля и связанных изменений launcher/tests/docs.
- Профиль и launcher меняются по согласованным этапам; код RuClaw не меняем.
- Этот файл — рабочий план аудита, не стартовый контекст Pi.

## Краткое состояние

Обзор backend, MCP, core wiring, DB isolation, settings и основных UI/worker
entry points выполнен статически. Полный security audit и CI/test topology не
завершены и не нужны как предварительное условие краткого профиля. Найдены
расхождения даже между inline docs и кодом. Outline согласован; подготовлены
новые `project.md`, `areas.md` и отдельная заменяемая карта `testing.md`.
Source-hash аудит удалён; launcher проверяет наличие наших файлов, не team docs.

## Как двигаемся

Один проход: исследовать ограниченную область → записать факты и пробелы со
ссылками → задать небольшой набор существенных вопросов → записать ответы →
уточнить выводы. Не нужно заранее прочитывать всю документацию.

Различать:
- **Подтверждено статически** — просмотрены конкретные код/настройки/тесты.
- **Проверено выполнением** — указаны реально выполненная команда и результат.
- **Гипотеза / не проверено** — требуется дальнейший просмотр или запуск.
- **Решение пользователя** — намерение/граница, а не доказательство реализации.

Наличие теста или CI job не означает, что он проходит или запускается во всех
режимах. Документированное и реализованное поведение при расхождении записывать
отдельно. Не запускать стенды, миграции, реальные LLM и тяжёлые проверки в рамках
первичного статического обзора.

## Этапы

- [x] Создать план и записать договорённости.
- [x] Первично осмотреть дерево, точку входа, часть Makefile и UI manifests.
- [ ] 1. Обзор системы: назначение, основные сценарии, исполняемые компоненты,
  точки входа, границы основного продукта и вспомогательных инструментов.
- [ ] 2. Backend: пройти один основной запрос от входа до исполнения и ответа;
  выяснить роли gateway, agent/runtime, tools, approvals, фоновых задач.
- [ ] 3. Данные и безопасность: PostgreSQL, tenancy/authz, identity, secrets,
  settings/bootstrap, migrations, object storage и sandbox.
- [ ] 4. Интерфейсы и сервисы: оба UI/API, Python/Node sidecars, MCP и каналы;
  отделить подключённое от просто присутствующего в дереве.
- [ ] 5. Разработка и доставка: фактические dev entry points, генераторы, тестовые
  уровни, CI job rules, Compose/Helm/release; проверить Git/changelog conventions.
- [ ] 6. Сверка документов по исследованным областям: полезные ссылки,
  подтверждённые противоречия и устаревшие описания. Не каталогизировать все архивы.
- [x] 7. Согласовать содержание и написать новые `project.md` / `areas.md`;
  текущую карту тестов вынести в отдельный `testing.md`.
- [x] 8. Удалить source-hash аудит; согласованно обновить launcher, тесты и README.
  Проверить загрузку контекста основным Pi; если отдельные роли сохраняются,
  проверить также их обращения к профилю. Запустить релевантные offline-тесты.

Этапы можно переставлять после ответов пользователя. Начальный обзор не является
завершённым архитектурным аудитом.

## Первый проход: подтверждено статически

Исследуется `/home/dyens/dev/croc/ruclaw`, начальный HEAD `d9d781038`.
При начале обзора `git status --short` пуст. Это точка отсчёта, не заморозка
быстро меняющегося проекта; при продолжении проверять изменения затронутых файлов.
Пути ниже относительно RuClaw, если явно не указано иное.

| Наблюдение | Основание | Что ещё выяснить |
|---|---|---|
| Главный Go entry point вызывает Cobra CLI; команда без подкоманды вызывает `runGateway()` | `main.go`, `cmd/root.go` | Реальный состав gateway и путь запроса; описание CLI само по себе не доказывает архитектуру |
| Есть отдельные entry points credbroker и sandboxshim, а также генераторы User API | `cmd/credbroker/main.go`, `cmd/sandboxshim/main.go`, `cmd/userapi-openapigen/main.go`, `cmd/userapi-contractgen/main.go` (пока только наличие файлов) | Ответственность, wiring, способы сборки/запуска |
| Одновременно присутствуют `internal/core/{domain,application}`, `internal/infra`, `internal/app` и множество пакетов вне этих слоёв | Первичный осмотр дерева `internal/` | Фактические зависимости и границы; нельзя пока объявлять всё layered architecture или legacy |
| Оба UI используют React/Vite/TypeScript, pnpm, React Router 8 и TanStack Query | `ui/web/package.json`, `ui/user-front/package.json` | Фактические маршруты, API, общее/раздельное состояние и дизайн-система |
| Admin manifest содержит HeroUI 3, Tailwind 4 и Zustand | `ui/web/package.json` | Реальное использование библиотек, а не только объявление зависимости |
| Makefile задаёт `GOFLAGS ?= -tags=goolm`, build использует `CGO_ENABLED=0` | `Makefile:1–16` | Согласованность остальных entry points и CI |
| Есть dev targets для host backend/fronts, fronts-only и Docker dependencies; `make up` вызывает launcher | `Makefile:26–106` | Проверить сами scripts; комментарии не гарантируют фактическую топологию |
| В CI есть группы проверок tenancy/RLS/core, UI, sandbox, стенда, а также сборки и release/deploy | Имена jobs в `.gitlab-ci.yml` | Прочитать scripts/rules и установить условия выполнения; успешность не проверена |

### Уже обнаруженная неточность личного профиля

`files/pi-ruclaw/profile/areas.md` описывает Admin UI как Router 7, тогда как
текущий `ui/web/package.json` объявляет `react-router ^8.3.0`.
Это подтверждённое расхождение описания с manifest, не проверка runtime.
Вывод: профиль нельзя считать актуальным только потому, что хеши CLAUDE совпали.
В итоговом профиле не перечислять версии библиотек без практической необходимости.

## Вопросы пользователю — первый набор

1. Как ты сейчас описал бы назначение RuClaw в 2–3 предложениях: для кого он и
   какие основные задачи решает? Это нужно как ориентир, чтобы не принять старое
   описание CLI/README за актуальное позиционирование.
2. Что уже известно как выводимое из эксплуатации, экспериментальное или
   заменяемое прямо сейчас? Особенно важны зоны активного переписывания: их
   наличие в коде не должно автоматически стать рекомендацией для новых изменений.
3. Есть ли приоритетная область для углубления после общей карты? По умолчанию:
   backend/runtime → данные и безопасность → UI/сервисы → dev/CI.

## Ответы и решения

Первый набор — получены ответы пользователя:

1. **Назначение:** корпоративный LLM-агент для централизованного использования
   сотрудниками компании. Доступен через Web и каналы, например Telegram.
   Подключается к корпоративным системам; безопасность — ключевой приоритет.
2. **Известная зона изменений:** скоро изменятся структура, состав и способ
   запуска тестов. Текущее устройство исследовать как временный снимок, не
   закреплять в профиле как долгосрочный контракт. Перед завершением профиля
   отдельно переспросить статус изменений и актуализировать тестовую карту.
3. **Приоритет согласован:** backend/runtime → данные и безопасность →
   UI/сервисы → dev/CI.

Эти ответы определяют фокус аудита, но не доказывают свойства реализации.

## Второй проход: сборка backend и начало пути сообщения

HEAD по-прежнему `d9d781038`, рабочее дерево RuClaw чистое. Все выводы ниже
статические; выполнение и полнота защиты не проверялись.

| Компонент / граница | Что непосредственно видно в коде | Основание |
|---|---|---|
| Главный процесс | Собирает provider/tool registry, message bus, object-store client, sandbox manager, gateway и User API | `cmd/gateway.go:215–334,1096,3204–3250`; просмотрены отдельные участки, не весь wiring |
| Bootstrap | Запуск вызывает `config.LoadBootstrap()` и `cfg.Validate()`; при ошибке завершает процесс | `cmd/gateway.go:232–237`; конкретные допустимые настройки ещё не исследованы |
| Object storage | Клиент создаётся при старте; ошибка загрузки credentials или создания клиента фатальна | `cmd/gateway.go:254–278`; доступность хранилища не проверена |
| Sandbox | Есть ветви Docker и Kubernetes; при недоступности Docker или ошибке проверки K8s isolation profile запуск завершается | `cmd/gateway.go:294–334`; это не доказательство изоляции всех инструментов |
| HTTP-поверхности | User API создаётся со своими authenticator/authorizer и bindings; вместе с gateway handler передаётся в основной listener | `cmd/gateway.go:3204–3250`; разделение маршрутов/middleware ещё проверить в реализациях |
| Канальный ingress | Consumer принимает сообщения, проверяет tenant и при наличии route fence перепроверяет привязку; выбирает агента и формирует session key | `cmd/gateway_consumer.go:469–633` |
| Запрос на исполнение | `RunRequest` содержит tenant, IAM identity/roles, agent/session, channel и ограничения/данные доставки; далее передаётся scheduler | `cmd/gateway_consumer.go:973–1069,1142` |
| Scheduler → agent | Callback устанавливает tenant/user/IAM context до `agents.Get`, затем вызывает `loop.Run` | `cmd/gateway_consumer.go:79–154`; cache/resolver ещё не прослежены |
| Начальная подготовка loop | Последовательно вызывает admission, session binding, registry/exposure preparation, runtime start и message policy | `internal/agent/loop_run_entry.go`; тела этих операций ещё не проверены |
| Credential broker | Самостоятельный процесс: команды migrate/up; up создаёт PG-backed store, MCP broker, A2A broker и HTTP server | `cmd/credbroker/main.go:47–93,166–240`; endpoint auth, allowlist и передача credentials требуют отдельного разбора |
| Sandbox shim | Отдельный HTTP-процесс с обязательным token, лимитами запросов/вывода/длительности; передаёт их router | `cmd/sandboxshim/main.go:169–229`; router и исполнение команд ещё проверить |

### Предварительная карта, не полный end-to-end trace

```text
Канальный ingress → message bus → consumer → RunRequest
  → scheduler → agent router/resolver → agent loop

Основной HTTP listener
  ├─ gateway handler
  └─ User API handler с отдельно переданными auth dependencies

Отдельные процессы: credential broker, sandbox shim
```

Путь от адаптера канала до bus, Web-путь, вызов LLM, исполнение обычного
инструмента и конечная доставка ответа ещё не прослежены полностью.
Не считать все входы одинаковыми и не утверждать, что все tools идут через sandbox.

### Что важно для будущего профиля

- Описывать границы доверия между пользовательским входом, подтверждённой IAM
  identity, агентом и доступом к корпоративным системам, а не только каталоги.
- Нельзя выводить полномочия из текста запроса или session key: уже в wiring
  отдельно передаются identity, tenant и agent routing. Полный контракт ещё выяснить.
- Различать пользовательский Web API и прочую gateway-поверхность; фактические
  потребители и middleware будут проверены далее.

## Вопросы пользователю — второй набор

1. Как в реальной эксплуатации используется tenancy: одна компания на установку,
   несколько компаний/подразделений в одной установке или оба варианта? Нужно
   понять смысл границы tenant, а не только наличие UUID/RLS в реализации.
2. Для подключений к корпоративным системам предполагаются личные credentials
   сотрудника, общие сервисные подключения или оба варианта? Какие ограничения
   принципиальны при доступе из групповых чатов? Это вопрос о нужной модели,
   фактические проверки будем выяснять по коду.

## Ответы пользователя — tenancy, MCP, группы

Это требуемая модель; соответствие реализации проверяется отдельно.

- **Tenant:** обычно департамент; на demo stand отдельные компании могут получать
  собственные tenants. Основное требование — изоляция tenants друг от друга.
  Нельзя рассчитывать на общую доверенную компанию внутри одной установки.
- **Создание MCP:** только tenant admin. Есть tenant-level и agent-level MCP.
- **Подключение MCP к агенту (уточнение пользователя):** по умолчанию у агента
  нет MCP. Конкретные MCP подключаются к нему явно. Наличие MCP в tenant само
  по себе не означает доступность всем агентам. Эта привязка определяет набор
  подключений агента; режим credentials отдельно определяет доступность вызова
  для текущей identity. Отдельный групповой допуск этим ответом не установлен.
- **Credentials:** возможны общие credentials, внесённые один раз и используемые
  разными агентами, и личные credentials пользователя для конкретного MCP.
  Credbroker проксирует обращения к upstream MCP и подставляет credentials
  пользователя; это важная граница доступа к корпоративным системам.
- **Групповые чаты:** доступность пока не определена. Если включены, агент
  рассматривает участников как anonymous, без доступа к приватной пользовательской
  информации и личным credentials. Это не означает автоматически отсутствие
  общей истории группы или запрет всех tenant-shared инструментов — эти границы
  ещё уточнить. Нельзя выдавать доступность групп за подтверждённое решение.

## Третий проход: MCP и личная identity

HEAD всё ещё `d9d781038`, но рабочее дерево RuClaw теперь изменено параллельной
работой: A2A broker/client/server, tools, tests. Не изменять и не включать эти
правки в наш аудит как согласованное состояние; A2A изучать позднее с повторной
проверкой diff. Просмотренные ниже MCP/identity файлы не отмечены изменёнными.

Подтверждено статически:

- `internal/mcp/manager_managed.go:81–173`: manager получает доступные агенту
  MCP из store, пропускает disabled, дополнительно проверяет owner agent-level
  сервера. Реализация SQL `ListAccessible` и полнота grants ещё не проверены.
- В том же методе независимо рассматриваются `none`, `shared`, `user_provided`:
  без credentials подключается напрямую; shared/user_provided — через broker.
  При отсутствии подтверждённого IAM UUID для user_provided регистрируется
  not-linked stub вместо подключения с произвольным channel user ID.
- `sharedBrokerPath` / `userBrokerPath` в том же файле разделяют credentials
  путями tenant/server, дополнительно agent для agent-level и user для личных
  credentials. Наличие отдельных путей само по себе не доказывает корректность
  авторизации, cache isolation и proxy endpoints.
- `cmd/gateway_consumer_identity.go:202–225`: групповому контексту возвращаются
  group key и пустой IAM UUID, но он **не ephemeral**. То есть anonymous здесь
  не означает отсутствие сохраняемого группового состояния. Авторизация
  чтения личных данных через остальные tools ещё не проверена.
- `internal/http/mcp.go:259–320`: создание MCP требует `PermMCPManage` через
  `requireCorePermission` и непустой tenant. Пока НЕ подтверждено, что такое
  permission может получить исключительно tenant admin: нужно проверить RBAC
  catalog/grants, а не доверять комментарию tenant-admin-only.
- `internal/credbroker/mcpbroker/gateway.go`: просмотрены интерфейсы и создание
  broker, разделение cache keys по path/label/credential+system revision.
  Сам proxy-вызов и подстановка headers ещё не прослежены.

### Промежуточный вывод

В описании MCP важно разделять две независимые оси:
**область подключения** (tenant/agent) и **режим credentials**
(none/shared/user_provided). Не путать tenant-level с shared credentials.

Групповой IAM UUID и проверка user_provided согласуются с требуемой моделью на
просмотренном участке. Это не доказательство отсутствия доступа к личным данным
во всей цепочке. Особо проверить shared MCP: общий service account upstream
сам по себе не гарантирует, что его данные допустимо показывать группе.

## Открытые вопросы после третьего прохода

- Пользователь уточнил базовую модель: явное подключение конкретных MCP к агенту,
  по умолчанию подключений нет. Не проектировать отдельный механизм групповых
  grants в рамках аудита. Сначала проверить существующие agent grants и фильтры
  identity. Отдельная политика групп остаётся неустановленной; требование
  «не раскрывать личные данные» сохраняется при любых credentials.
- Проверить по коду: кто может получить `PermMCPManage`; не задавать пользователю
  вопросы о деталях реализации, которые можно выяснить самостоятельно.

## Четвёртый проход: сверка MCP с кодом

По просьбе пользователя его описание проверяется как гипотеза, а не принимается
за точное описание реализации. Статическая сверка, без запуска тестов и upstream.
В рабочем дереве продолжаются сторонние A2A-изменения; их не трогали.

### Фактический выбор подключений

`internal/store/pg/mcp_servers_access.go:182–200`, runtime-метод `ListAccessible`:

| Вид MCP | Когда попадает в набор подключений агента |
|---|---|
| tenant-level | Сервер enabled И есть enabled grant `mcp_agent_grants` на данного агента |
| agent-level | Сервер enabled И `owner_agent_id` совпадает с агентом; отдельный grant НЕ требуется |

Таким образом, описание «конкретные MCP подключаются к агенту» верно, но
не каждое подключение оформляется отдельным grant: для agent-level сама запись
владельца уже задаёт доступ. Удаление grant не отключает принадлежащий агенту MCP.

Это также видно в `internal/store/pg/equipment.go:446–491`: agent-owned MCP
показывается как `agent_default`, не removable через обычный список equipment.
Tenant MCP — direct equipment. Наличие записи в каталоге tenant не даёт
автоматического доступа всем агентам.

**Оговорка про «по умолчанию нет MCP»:** runtime не открывает весь каталог,
но provisioning может заранее создать привязки. В `cmd/seed_mcp.go:77–120`
dev `--from-env` seed при явно выбранном MCP и незаданном списке AGENTS
подставляет default agent. Поэтому на подготовленном dev stand MCP может
появиться у агента без ручного клика в UI. Это не глобальное runtime-умолчание.

### Кто подключает и кто управляет

- Создание: `POST /v1/mcp/servers` → `h.auth(PermMCPManage, ...)`
  (`internal/http/mcp.go:259–266`). `coreAuthorize` без явного ресурса проверяет
  tenant принципала / pinned tenant (`internal/http/core_gate.go:480–508`).
  В стандартных ролях `tenant_admin` имеет `PermsMCPManage`; `tenant_member`
  не имеет `mcp:manage`. `agent_admin` имеет это permission на скоупе агента,
  что само по себе не даёт права создать через tenant-scoped endpoint.
- Это permission-based gate, не буквальная проверка имени роли. Есть также
  service principals/API token constraints и fallback legacy admin при
  неинициализированном shared rights; штатный gateway задаёт shared core RBAC
  в `cmd/gateway.go:1394`. Полный аудит всех видов principal ещё не завершён.
- Отдельный grant из management API требует `mcp:equip` на tenant; handler
  проверяет наличие сервера и агента в текущем tenant
  (`internal/http/mcp.go:2102–2161`).
- **Подключать существующие MCP может не только tenant admin:** User API
  `replaceEquipment` проверяет `agent:update`, `skill:equip`, `knowledge:equip`,
  `mcp:equip` на агенте (`internal/userapi/equipment_transport.go:53–73`).
  Стандартная роль `agent_admin` содержит эти permissions. PG equipment
  валидирует выбранные MCP в tenant: tenant-level либо owned этим агентом
  (`internal/store/pg/equipment.go:252–254`).
- Agent admin также может менять credentials mode существующего собственного
  agent-level MCP и записывать shared credentials через отдельные endpoints;
  это не создание нового endpoint/изменение URL
  (`internal/http/mcp.go:647–746,785`; роль — `core/domain/rbac/role.go:173–205`).

### Credentials и proxy

Подтверждается описание пользователя, с дополнениями:

- `none`: прямое подключение к upstream; `shared` и `user_provided`: через broker
  (`internal/mcp/manager_managed.go:111–171`). Не трактовать `none` как гарантию,
  что на всех уровнях отсутствует service authentication: есть отдельные
  server/template headers и upstream service token.
- Путь shared credentials: tenant/server, для agent-level tenant/server/agent.
  Путь личных credentials: tenant/server/user либо tenant/server/agent/user.
- Для `user_provided` нужен verified IAM UUID; без него runtime ставит stub.
  Сам факт подключения MCP агенту не даёт личные credentials другого пользователя.
- Gateway подключается к broker `/mcp` с per-server bearer и `X-Broker-Path`,
  не отправляет upstream credentials из server headers в этот вызов
  (`manager_managed.go:382–439`).
- Broker `CallUpstreamTool` разрешает system и secret по path, выбирает account
  по необязательному `account_id`, строит credential headers из descriptor,
  объединяет с service authentication и вызывает upstream
  (`internal/credbroker/mcpbroker/tools.go:78–190`). Следовательно, у одного
  пользователя/пути может быть несколько accounts, а не строго один секрет.
- Grant дополнительно ограничивает tools: deny имеет приоритет, непустой allow
  выбирает разрешённые имена; `*` в allow означает все. Без allow ограничений
  регистрируются все допустимые discovered tools, кроме явно запрещённых
  (`manager_managed.go:332–367`). Остальные runtime policy gates ещё исследуются.

### Группы: что установлено и что не установлено

У группы пустой verified IAM UUID; поэтому через просмотренный managed MCP
loader она не получает user-provided credentials. У shared/none ветвей этого
условия нет: при доступности MCP агенту loader сам по себе не требует личной
identity. Из этого НЕЛЬЗЯ заключить, что все shared MCP фактически доступны во
всех группах: до/после loader есть channel admission и tool policy.

Также найдена отдельная domain-модель `internal/core/domain/mcp.go` с
`AnonymousUsage`, `DefaultAccess` и `AgentRules`. Эти поля нельзя автоматически
приписать runtime SQL loader: у него другая модель выбора (таблица grants и
owner). `AccessFor` вызывается в core execution/equipment; требуется проследить
адаптеры и связность с live agent execution. Особенно не полагаться на комментарий
в роли о запрете user_provided × anonymous как на доказательство runtime guard.

### Итог сверки для будущего профиля

«MCP задаются в пределах tenant. Tenant-level подключения выдаются агентам
явными grants; agent-level принадлежат конкретному агенту и доступны ему без
отдельного grant. Создание подключений и оснащение агента — разные полномочия.
Режим credentials независимо определяет, используется общий или личный account
через credbroker. Личная identity должна быть подтверждена».

Это черновая формулировка по просмотренным путям, не готовый полный security contract.

## Уточнения пользователя: dev environment, installation scope, DDD

### Окружение разработки

Dev seed — наши инструменты настройки окружения, не поведение продукта.
Текущий рабочий порядок со слов пользователя:

```text
make up (Docker dependencies) → go build → ruclaw migrate up
  → ruclaw → make seed → make front-up
```

Команды записаны как описание практики пользователя, не как проверенная инструкция
для запуска. Перед включением в карту разработки сверить точные имена targets и
CLI: в просмотренных фрагментах Makefile были `dev-fronts`, `dev-fronts-only`,
`dev-seed`, а `dev-migrate` вызывал `upgrade`. Не объявлять расхождение ошибкой
пользователя или кода до проверки актуальных launchers. Не запускать этот цикл
в ходе статического аудита. В кратком описании продукта dev seed не нужен.

### Installation Admin и изоляция

- Installation Admin — специфическая роль глобальной настройки над tenants.
  По описанию пользователя, соответствующие операции работают в обход PG RLS.
- Не путать наличие технического bypass RLS с разрешением читать любые tenant
  данные. Проверить границы control plane, полномочия и места использования
  maintenance/bypass connection по фактическому wiring.
- Остальные tenant-scoped роли работают в конкретном tenant и обязаны сохранять
  его изоляцию. Пользователь упомянул tenant-admin, tenant-manager и другие роли;
  фактический каталог имён/permissions ещё сверить, не создавать роль из упоминания.
- Bypass не должен становиться обычным способом выполнения tenant-сценариев.
  Конкретные допустимые исключения и их проверки — предмет security-прохода.

### Архитектурное направление: постепенное DDD

**Это явное намерение пользователя для будущих изменений, а не утверждение о
завершённой миграции существующего кода.**

- Domain-модель в зачаточном состоянии; раньше её не было. Проект постепенно
  вводит DDD, поэтому core-модель и live implementation могут расходиться.
- Новые фичи и рефакторинг по возможности делать в этом направлении: бизнес-логика
  должна находиться в core, быть хорошо читаемой человеком.
- Не копировать существующий обход core только потому, что он уже встречается.
  Но и не затевать тотальную миграцию проекта ради небольшой задачи.
- При аудите разделять **как работает сейчас**, **какое направление принято** и
  **какой участок уже переведён и реально подключён**. Наличие domain-типа не
  доказывает его использование в runtime; старый runtime не отменяет направление.
- Не навязывать сложные DDD-паттерны ради терминологии: основной ориентир —
  явные бизнес-правила, понятная модель и читаемость для команды.

В будущем `project.md` нужны и текущая карта системы, и короткое описание этого
архитектурного намерения. Одного снимка фактических зависимостей недостаточно.

## Пятый проход: Web chat, runtime и степень подключения core

Точка обзора теперь `ac612deef`; рабочее дерево RuClaw чистое. Между начальным
`d9d781038` и текущим HEAD закоммичены ранее наблюдавшиеся изменения A2A
(12 файлов); по `git diff --stat` они не меняют просмотренный Web/runtime path.
Аудит статический: код не запускался, поведение не проверялось тестами.

### Web chat не сводится к REST User API

Прослежен основной путь User Front:

```text
ui/user-front: user-chat-adapter.ts
  → WS RPC user.chat.send
  → gateway/methods/user_chat.go: handleSend
  → проверка actor + agent:talk, принадлежность существующей сессии
  → coordinator reservation + Store.AcceptUserFrontMessage
  → Router.Get → отдельная goroutine → Loop.Run
  → события user.chat.* / CompleteUserFrontRun
```

- UI вызывает `transport.request("user.chat.send", ...)`
  (`ui/user-front/src/realtime/user-chat-adapter.ts:236–259`).
- `handleSend` берёт tenant/owner из gateway client, а не из тела запроса;
  проверяет `agent:talk`, существующую сессию ищет по tenant/owner и сверяет
  агента. Есть replay по client message ID, reservation и отдельная фиксация
  принятия сообщения (`internal/gateway/methods/user_chat.go:228–383`).
- В этом пути `Loop.Run` вызывается напрямую, НЕ через тот же scheduler callback,
  что у канального consumer. Передаются подтверждённые IAM owner/tenant,
  `ExternalTerminalCommit` и callback событий (`user_chat.go:457–630`).
- Итоговое сохранение ответа делает Web handler через `CompleteUserFrontRun`;
  ожидание approval, ошибки и outcome_unknown имеют отдельные ветки
  (`user_chat.go:732–893`, изучен участок, не весь recovery path).
- `DispatchUserFrontEvent` доставляет события только IAM-backed клиентам того же
  tenant и того же actor UUID. Это отдельный dispatcher, не общая рассылка
  (`internal/gateway/user_front_dispatch.go`). Полная WS аутентификация и SQL
  сессий пока не проверены — это не доказательство общей безопасности Web API.

Уточнение к ранней карте: REST User API и WS chat — разные поверхности.
HTTP-конфигурация User API сама по себе не описывает авторизацию/исполнение чата.

### Общая часть agent execution

- `Loop.Run` выполняет begin → prepare → execute → finalize;
  continuation rounds заново проходят admission и сборку контекста
  (`internal/agent/loop.go:287–340`, `loop_run_execution.go`).
- Запрос к модели проходит подготовку primary pipeline и bounded deadline,
  затем masked provider call. Transport вызывает `provider.Chat` либо
  `ChatStream` (`loop_primary.go:36–153`, `loop_provider_transport.go:32–83`).
- Для просмотренной serial tool ветки перед выполнением вызывается before-tool
  guardrail, возможна пауза с сохранением approval, затем перепроверяется exposure
  (`loop_serial_tool_turn.go:73–217`). Parallel/recovery ветки отдельно не доказаны.
- Физическое выполнение идёт через `executeRunTool` →
  `Registry.ExecuteWithContext` → конкретный `Tool.Execute`. Registry повторно
  проверяет disabled/denied, execution gate, live deny, аргументы и при наличии
  durable admission (`ordinary_execution.go:168–222`, `tools/registry.go:402–533`).
- Нельзя описывать защиту как один RBAC check на входе или считать любой tool
  sandboxed. Это несколько границ, а физический механизм зависит от tool.

### Что из core уже работает, а что пока заготовка

**Подключённые примеры:**
- RBAC/tenancy собираются через `internal/app/rbac.go`; gateway вызывает
  `app.NewRBAC`, подключает agent lifecycle и передаёт rights в HTTP/gateway
  (`cmd/gateway.go:1369–1404`). Это реальный пример core + infra adapters,
  но не доказательство миграции всех операций tenancy.
- Approvals: `cmd/gateway_checkpoint_module.go` создаёт PG adapter, authority и
  `core/application/approval.Service`, соединяет их с runtime; конструкции
  видны в `newCheckpointApprovalModule`, особенно строки 169–182.

**Заготовка, которую нельзя выдавать за действующий executor:**
- `internal/core/application/execution/service.go` содержит `CallMCPTool`,
  `SpawnSubagent`, `ResumeInterruptedRun` и другие сценарии с явными `panic`
  «СТАТУС: под вопросом». Даже `CallMCPTool` после проверок не делает proxy-call.
- Поиск импортов `core/application/execution` в Go-коде репозитория не дал
  совпадений; LSP references для его `NewService` также пусты. В просмотренной
  живой цепочке tools исполняются через registry, не этот сервис.
- Поэтому domain `MCPServer.AccessFor`, `AnonymousUsage` и `DefaultAccess`
  нельзя использовать как достоверное описание runtime grants/anonymous gates.
  Их наличие выражает модель, но не доказывает подключение к продукту.

**Вывод для профиля:** core вводится постепенно. Для изменения нужно установить,
какой сценарий уже подключён; новые бизнес-правила стремиться выразить в core и
соединить с runtime, а не ограничиться красивой моделью рядом с прежним поведением.
При этом не пытаться просто переключить runtime на незавершённый execution service.

## Шестой проход: PostgreSQL, tenant context, installation scope и broker auth

HEAD `ac612deef`, рабочее дерево чистое. Всё ниже — статический просмотр;
не проверялись реальные DB roles, применённые миграции и live RLS policies.
Это уточнение карты и инвариантов профиля, не полный security audit продукта.

### Уровни изоляции данных

1. **SQL-level scoping:** `internal/store/pg/tenant.go` централизует
   `writeTenant`, `queryTenant`, `appendTenantFilter` / `tenantFilterCol`.
   Tenant берётся из ctx; есть legacy/default fallback и strict modes.
   По телам функций strict reads без tenant дают zero-UUID фильтр, strict writes
   дают SQL NULL вместо default tenant. В `ApplyStrictTenancy` оба режима
   включаются при числе tenants > 1; gateway вызывает его при старте.
   Runtime-переход при создании второго tenant ещё отдельно не прослежен.
2. **DB-level RLS:** `rlsconn.go` в implicit transaction выставляет
   `SET LOCAL app.tenant`; в явной transaction tenant фиксируется на BeginTx.
   SQL внутри открытой tx не переключает tenant по новому ctx
   (`rlsconn.go:503–623`). Поэтому переставить tenant в ctx внутри чужой tx —
   НЕ способ переключить DB scope.
3. **RLS tenant delivery по умолчанию включена:** тело `rlsTenantScopeEnabled`
   возвращает true для unset и неизвестного значения; выключают только явные
   off/false/0/no/n (`rlsconn.go:116–132`). Комментарий в `pool.go:34–39`
   утверждает старое off-by-default — подтверждённая устарелость даже inline docs.
4. `NewPGStores` проверяет app DB role и maintenance pool. При наличии RLS в БД
   app role с superuser/BYPASSRLS отклоняется; отсутствие maintenance pool тоже
   фатально. Maintenance role проверяется на реальный bypass
   (`factory.go:18–39,176–260`). Это startup guards, а не доказательство, что
   текущий стенд действительно сконфигурирован правильно.

### Обычный pool и cross-tenant pool — разные возможности

- `base.q(ctx)` использует обычный pool либо caller tx; `beginTx` запрещает
  неявное вложение, `joinTx` явно присоединяет к caller tx
  (`querier.go:47–170`).
- `crossTenant` идёт через отдельный maintenance pool, а не `SET ROLE`.
  Есть специальная обёртка `crossTx`, не выдающая `*sql.Tx`, чтобы обычный
  `WithTx` случайно не распространил bypass по всему call tree
  (`querier.go:174–309,371–422`; просмотрены routing и типовая конструкция).
- Это НЕ механизм только для Installation Admin: он нужен также системным
  cross-tenant операциям (например глобальная identity lookup и выбор фоновых
  работ). Наличие bypass в процессе не определяет полномочия его пользователя.
- `scripts/db/provision-roles.sql` создаёт отдельные app (NOBYPASSRLS), maint
  (BYPASSRLS), owner и broker roles. Не выводить из одного имени роли/DSN,
  что полномочия действительны — есть runtime assertions.

### Tenant context: liveness не равна авторизации

`tenantctx.With` проверяет ненулевой UUID и liveness, затем ставит tenant в ctx.
Это НЕ проверка членства пользователя или его permissions. Она нужна отдельно
на transport/application границах. `Propagate` не проверяет даже liveness:
переносит уже допущенный tenant; нельзя использовать как admission произвольного
UUID из запроса (`tenantctx.go:174–208,266–316`).

Gateway ставит cached liveness source (`cmd/gateway.go:726`); без configured
source код допускает tenant с предупреждением. Поэтому сам вызов `With` без
проверки wiring ещё не доказывает контроль удалённых tenants.

### Installation Admin: разделение подтверждается, но не через RLS-роль человека

- RBAC роль и PostgreSQL role — разные сущности. Продуктовая роль не означает
  выдачу человеку прямого DB connection с BYPASSRLS.
- `domain.Tenant.ResourcePath()` не содержит installation; `ResourceRef.Covers`
  сопоставляет только элементы пути. Следовательно, grant на installation
  автоматически не покрывает tenant (`core/domain/tenant.go:56–69`,
  `resource.go:137–147`).
- Есть явный core bridge `AssignTenantAdmin`: проверяет installation permission,
  выдаёт только tenant_admin, сохраняет source `GrantedByInstallation` и пишет
  audit (`core/application/rbac/bridge.go`). Найден production caller при
  provisioning tenant (`tenancy/provision_tenant.go`). Не считать самостоятельный
  UI/API «назначить себя» реализованным лишь из комментариев этого сервиса.
- У роли Installation Admin есть control-plane permissions; точный список
  текущих ролей смотреть в `core/domain/rbac/role.go`. `tenant_manager` в этом
  просмотренном каталоге не найден — пока не включать его в описание как
  существующую встроенную роль.
- `tenancy.Impersonate` по телу только проверяет право и пишет audit, не выпускает
  сессию. В production Go-коде вызовов `.Impersonate(...)` не найдено. Не включать
  обещанную в комментарии временную impersonation-сессию в описание возможностей.

### Credbroker: token связан с системой, не с личностью конечного пользователя

- `server/server.go` монтирует `/mcp` через `requireSystemToken`, management
  `/v1/` через отдельный admin bearer. Проверены именно MCP/management gates;
  A2A имеет другие entry points и здесь не аудировался.
- MCP middleware парсит `X-Broker-Path`, разрешает system, сравнивает hash bearer
  с токеном этой system и проверяет expiry (`server.go:177–207`). Токен другой
  системы не проходит это сравнение.
- На этой границе broker НЕ аутентифицирует конечного IAM user. Вызвавший gateway
  выбирает user suffix пути; per-system token сам по себе не доказывает право
  человека на каждый account под system prefix. Это доверенная связь gateway ↔
  broker, и сохранение verified identity до построения path принципиально.
- Структуру `SystemFor`/prefix matching, management access, redaction и cache
  isolation целиком ещё не проверяли. Не объявлять изоляцию broker доказанной.

### Что попадёт в компактный профиль, а что останется в аудите

В ядре нужны только инварианты: tenant isolation, отдельная авторизация identity,
app-vs-maint boundary, сохранение tenant/tx scope и запрет обходить эти механизмы.
Конкретные флаги strictness, детали driver и доказательства — в карте области/этом
аудите, не в обязательном стартовом описании. Иначе снова получится workflow.md.

## Седьмой проход: anonymous/group, settings и секреты

HEAD `ac612deef`, рабочее дерево чистое. Статический обзор; live настройки и
данные не читались. Не открывались .envrc/models.yaml, credentials не извлекались.

### Anonymous — identity и policy, не универсальный запрет tools

- `tools/exposure_resolver.go:152–187` определяет anonymous как отсутствие
  verified IAM UUID И trusted roles. Явный anonymous с IAM UUID/roles отвергается.
  В обычном канальном consumer roles разрешаются только при непустом IAM UUID
  (`cmd/gateway_consumer.go:638–669`); у групп UUID пуст.
- Для anonymous добавляются `Unauthenticated` слои из глобальной и tenant
  policy. Наличие anonymous НЕ включает встроенный blanket deny всех tools:
  отсутствующий policy слой ничего не сужает. Каждый eligibility слой может
  только сузить предыдущий набор; скрытие из visible набора не следует путать
  с запретом execution (`exposure_resolver.go:188–349`).
- Поэтому shared/none MCP нельзя объявлять запрещёнными в группах только из
  слова anonymous. MCP grants, tool policy, identity и data ACL — разные проверки.
  User-provided MCP по ранее просмотренной ветке требует verified IAM UUID.
- `agent/loop_run_tools.go:81–89` удаляет `skill_offer` для group/ephemeral/
  unattended; сам tool также проверяет это. Это конкретный запрет, не правило
  для всех инструментов. Delegated/parallel/recovery identity propagation целиком
  не проверены; не делать универсального заключения по одному ingress path.

### Личные данные и собственное состояние группы

- Memory tools получают private owner только через verified IAM UUID;
  free-form UserID не считается authentication authority
  (`store/context.go:173–184`, `tools/memory.go:55–85`). При отсутствии owner
  tools возвращают отказ/skip. Есть отдельное исключение trusted background
  memory для shared facts — не приписывать его обычным anonymous/group запускам.
- Группы не ephemeral: у них может сохраняться групповое состояние. Запись
  защищённых context files проверяет group writer policy, с отдельным bootstrap
  исключением (`tools/context_file_interceptor.go:258–309`). Это не личное
  хранилище сотрудника, но полноценный изменяемый ресурс со своими правами.
- Cron тоже поддерживает групповые операции: verified group-author context и
  group writer permission; AuthorID используется для ownership, а execution
  остаётся anonymous (`tools/cron.go:155–190`). Значит «anonymous» не равно
  «только read-only». Полная безопасность knowledge/documents/artifacts пока
  не установлена; отсутствие IAM UUID не доказывает отсутствие всех утечек.

### Конфигурация: три разные категории

| Категория | Фактическая точка входа |
|---|---|
| Bootstrap / topology / installation identity | `config.LoadBootstrap()` → встроенные defaults + `applyBootstrapEnv` |
| Поведенческие настройки | PG registry: domain schema/validation → core settings service → infra adapter |
| Provisioning | Одноразовый seed/import, записывающий нужное состояние; не параллельный runtime config source |

- `LoadBootstrap` не читает config.json (`config/config_load.go:93–116`).
  Существование файла в дереве не доказывает его runtime использование.
- `Config.Validate` вызывает `PreflightEnv`. Непустые retired env variables и
  `RUCLAW_CONFIG` останавливают запуск; ошибка выводит имена и migration hints,
  не значения (`config/dead_env.go:167–201`). Не возвращать старые env overrides.
- Settings — уже подключённый core-модуль: `app.NewSettings` создаёт PG adapter,
  installation/tenant readers и explicit tenant-overrides reader;
  gateway собирает его на строке 581 и загружает secret settings на строке 779.
- Precedence «tenant > installation > default» существует только для ключей,
  допускающих tenant override. Большинство настроек installation-wide;
  нельзя обещать tenant admin возможность менять любое поведение своего tenant.
- Generic settings writer проверяет installation-level permission. Узкие
  tenant self-service поля могут иметь отдельную дверь; например ui.theme
  описана в core write contract. Её HTTP wiring здесь ещё не проверено.
- Typed `Value` возвращает ошибку чтения; convenience getters могут логировать
  ошибку и возвращать registry default (`settings/service.go:383–438`). Поэтому
  «динамическая настройка из БД» не гарантирует одинаковый fail-closed режим
  для всех consumers. Не менять эту семантику вслепую при миграции.

### Secret storage: не всё живёт в credbroker

- Личные/shared accounts корпоративных MCP идут через broker. Его secret
  module использует `secretbox`, отвергает non-empty нешифрованные/повреждённые
  значения (`internal/credbroker/secret/secret.go`); PG `SaveCredential` вызывает
  Seal, `ResolveSecret` — Open (`credbroker/store/pg.go:107–116,346–355`).
- Секретные installation settings хранятся в settings registry, не в broker.
  PG adapter шифрует новые записи через AES-GCM и маскирует audit значения;
  API SetResult возвращает mask (`infra/pg/settings/settings.go:55–105`,
  `core/application/settings/write.go:203–224`).
- Чтение registry secret использует совместимый `crypto.Decrypt`, не Strict:
  принимает legacy plaintext, а также возвращает исходную строку для некоторых
  malformed prefixed значений. Это видно по телу `internal/crypto/aes.go:55–98`,
  а не только комментарию адаптера. В broker такого fallback нет. Не утверждать,
  что всё existing secret storage строго encrypted-at-rest: реальные строки
  БД не проверялись; compatibility поведение зафиксировать отдельно.
- Bootstrap secrets (например DB connections / encryption key) — ещё одна
  категория. Не переносить их в registry за той БД, которую они открывают.

### Что нужно будущему профилю

Коротко: verified identity отдельно от routing UserID; anonymous не означает
полный запрет tools; private data требует собственных ACL. Конфигурация —
bootstrap + registry, без новых config.json/env обходов. Credbroker и secret
settings — разные хранилища. Технические ветки и compatibility нюансы оставить
в selective map/аудите, не разворачивать их в постоянном project context.

## Восьмой проход: UI/сервисы, dev launch и Git conventions

HEAD `ac612deef`, рабочее дерево чистое. Статический просмотр; scripts не
исполнялись, зависимости не ставились, docker/модели не запускались.

### UI и сервисы: карта реализации, не весь deployment inventory

| Часть | Что подтверждено | Точки входа |
|---|---|---|
| User Front | Пользовательские chat/tasks/agents/skills/knowledge/settings screens; REST User API + отдельный WS chat | `ui/user-front/src/app/router.tsx`, `src/realtime/user-chat-adapter.ts`, `internal/userapi/`, `gateway/methods/user_chat.go` |
| Admin Front | Управление ресурсами/настройками/аудитом; есть также public guest/credential-link/call routes вне admin shell | `ui/web/src/routes.tsx:237–302`; наличие маршрута не заменяет backend authorization |
| Shared UI | В дереве есть `ui/design-system`, оба manifest используют theme check generator | `ui/*/package.json`; применение всех generated tokens здесь не проверено |
| STT / TTS | Rabbit task consumers на основе общей sidecarworker library; Go queue clients в gateway | `services/stt/src/sttworker/app.py:85`, `services/tts/src/ttsworker/app.py:121`, `internal/stt/queue.go`, `internal/tts/queue.go` |
| DocService | Есть HTTP API и Rabbit worker, Go client выбирает HTTP/rabbit transport | `services/docservice/app/{main,queue_worker}.py`, `internal/docservice/client.go:43–131`; Compose отдельно запускает queue worker |
| Playwright | Отдельный Node/Playwright HTTP service | `playwright-service/package.json`, `index.js`; все endpoints и browser isolation здесь не проверены |
| Worker infrastructure | Независимые uv projects и собственные lockfiles, path dependency на sidecarworker | `services/{stt,tts,docservice,sidecarworker}/pyproject.toml`, их `uv.lock` |

Не описывать все sidecars как FastAPI/HTTP. Queue operation и HTTP health/control
plane могут сосуществовать. DocService всё ещё имеет обе реализации, выбор
`DOCSERVICE_TRANSPORT` берётся из bootstrap (`config/config_load.go:219`);
не объявлять переезд на очередь завершённым для всех режимов.

**Устаревшие обобщения:** `services/README.md` ещё говорит о будущем TTS и
будущем Rabbit DocService, хотя код обоих уже есть. Он полезен для объяснения uv,
но не как точная карта текущих процессов. DocService также НЕ использует общий
src-layout: package `app/` лежит в корне сервиса; его ruff include ограничен
`app/queue_*.py`, mypy тоже выбирает конкретные files. Поэтому фраза «для всех
Python сервисов весь код проверяется ALL/strict» была бы неверна.

### Точные dev entry points в текущем checkout

- `make up` → `scripts/dev/local-compose-up.sh`: base + dev Compose,
  `COMPOSE_PROFILES=dev` по умолчанию. Launcher не просто запускает контейнеры:
  собирает sandbox/firewall images, поднимает postgres, provision DB roles,
  запускает/проверяет broker init и выбранные one-shots, ждёт long-running
  services. Для app/all есть дополнительный seed/postcondition.
- Таким образом, сказанное пользователем «make up поднимает зависимости» описывает
  обычный host dev сценарий, но состав зависит от профилей. Не использовать его
  как обещание, что app/all тоже оставляет gateway на host.
- В Makefile нет `make seed` и `make front-up`. Есть `make dev-seed`,
  `make dev-fronts` и `make dev-fronts-only`; не запускались.
- `dev-seed` собирает бинарник, вызывает `migrate up`, seed-admin/fixture users и
  `seed --from-env`. То есть отдельный `migrate up` перед ним может повторять
  часть операции. Seed содержит dev-only настройки, не продовый runbook.
- `dev-fronts` через `scripts/dev-fronts.sh` собирает/запускает gateway и оба UI;
  `dev-fronts-only` запускает только UI для отдельно управляемого gateway.
  User Front на 5173, Admin upstream на 5174; `/admin/` проксируется через 5173.
- `ruclaw migrate up` реально существует, это не ошибка в описании пользователя.
  Дополнительно есть `make dev-migrate` с `ruclaw upgrade`; соотношение upgrade
  и ручного migrate не переносить в запусковую инструкцию без отдельной сверки.
- Launcher берёт `.envrc` main checkout через Git common-dir. При аудите файл
  не читали и не выполняли. Не советовать копировать credentials в worktrees.

### Git/changelog: какие ссылки оставить

1. `docs_flow/pravila-raboty-s-git.md` — именование/branch/MR/release policy;
   существующий bundled `skills/git-workflow/SKILL.md` ссылается на него.
2. `docs_flow/changelog.md` — точные trailers/exclusions и первое multiline
   commit body MR. Одной ссылки на общий Git документ для changelog недостаточно.
3. `scripts/ci/check-commit-message.sh` и `scripts/ci/check-changelog.sh` —
   исполняемые проверки; соответствующие jobs видны в `.gitlab-ci.yml:525–550`.

Прочитаны оба документа целиком, просмотрены проверки. Подтверждается правило
одного MR changelog decision в первом multiline commit (не каждого fix-коммита).
Но не весь Git документ актуален: раздел секретов ссылается на старые env/config
правила, раздел миграций описывает guard как ещё не настроенный, хотя job уже
присутствует. В профиле ссылка должна быть **тематической**, не импортировать
весь документ как источник архитектуры/config/security. Protected branches и
approve settings по GitLab API не проверялись; документы описывают политику.

## Предлагаемый outline профиля — на согласование

### `profile/project.md`: ориентир 1–2 экрана, без workflow

1. **Назначение.** Корпоративный LLM agent: Web/каналы, централизованное
   использование и корпоративные интеграции; безопасность — ключевой приоритет.
2. **Грубая карта системы.** Go gateway/runtime, PostgreSQL, object storage,
   sandbox, credbroker, два UI, специализированные sidecars. Не список всех
   пакетов/зависимостей и не перечень версий.
3. **Архитектурное направление.** Постепенное DDD: читаемая бизнес-логика в core;
   runtime мигрирован частично. Проверять wiring, не выдавать draft за реализацию.
4. **Границы данных/доверия.** Tenant isolation, verified identity vs routing ID,
   installation control plane vs tenant data, личные credentials через broker.
   Группы, если включены, без личных данных; фактическое покрытие guards не
   объявлять полностью доказанным.
5. **Конфигурация.** Bootstrap topology/identity + PG settings registry;
   не вводить параллельные runtime config/env backdoors.
6. **Навигация и conventions.** Читать релевантную область `areas.md`,
   технические документы не считать актуальными по названию. Явные ссылки на
   Git и changelog conventions перед Git/commit/MR действиями; без пересказа
   процедур и без перечня review/runner/evidence/handoff правил.

### `profile/areas.md`: короткая selective map

Область → реальные code entry points → проверенные полезные документы /
генераторы / package commands. Основные строки: backend/runtime; tenant/RBAC/PG;
MCP/credbroker; settings; UI/User API; sidecars; dev/build; Git/changelog.
Тесты отметить как меняющуюся область и актуализировать перед финализацией.
Для docs со смешанной актуальностью пометить назначение ссылки/ограничение.

### Не включать в постоянный контекст

Историю аудита, HEAD снимков, расхождения inline comments, все старые specs/ADRs,
таблицы криптографических режимов, полный CI/deployment inventory, процедуры
runner/review, handoff/evidence и шаблон checkpoint. Ссылки по необходимости,
без новых manifests или обязательного startup чтения этого plan.md.

## Вопросы перед черновиком

1. Подходит ли этот состав `project.md` и `areas.md`? После согласования можно
   написать сами файлы, не дожидаясь проверки каждого security edge case.
2. Тестовая реорганизация уже определилась или пока помечаем тестовую строку
   карты как временную и возвращаемся к ней позднее? Не нужно сейчас утверждать
   текущую CI topology как долгосрочную.

## Решение пользователя и подготовка профиля

- Outline одобрен. Тесты описываем текущие, но так, чтобы карту было просто
  проаудировать и заменить после реорганизации.
- Будущий подход со слов пользователя: больше независимых scopes; пример формы
  `TEST_TYPE=e2e_aaa,e2e_bbb make test run`. Это направление/пример, НЕ подтверждённый
  синтаксис существующего dispatcher. Не выполнять как рабочую команду.
- Переписаны `profile/project.md` и `profile/areas.md`. Процедурные инструкции
  runner/review/handoff/evidence убраны из project, не перенесены в новые файлы.
  ADR/domain больше не объявляются универсальной истиной.
- Добавлен `profile/testing.md`: текущие entry points, prerequisites/изоляция,
  skip semantics и чеклист замены при новом scope dispatcher. Только selective
  reading из areas, не отдельный системный prompt. После миграции менять в первую
  очередь его, а не повторять аудит всего проекта.
- Дополнительно просмотрены реальные test recipes, E2E selectors и testinfra
  gates. В текущем коде уже есть `E2E_GROUPS` для report и `E2E_SUITES` для smoke;
  не путать их друг с другом или с будущим `TEST_TYPE`.
- Сохраняем известную оговорку: wiring targets удаляют фиксированно названные
  контейнеры. Не запускать их без проверки ownership/concurrent use.

Проверки после подготовки профиля:
- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s files/pi-ruclaw/tests -p 'test_*.py'` — 9 tests OK.
- `node files/pi-ruclaw/tests/runtime-smoke.mjs` — PASS: реальный resource loader
  загружает project profile; личный context, skills и role definitions сохраняются.
  Это не LLM-проверка понимания или качества профиля.
- Локальные Markdown links и наличие обоих Git/changelog документов проверены
  отдельным Python assertion check — OK.
- LSP для Markdown не настроен; диагностик от него нет.

Продуктовые Go/UI/Python тесты и live стенды не запускались: изменён личный
Markdown контекст, не код RuClaw.

## Упрощение launcher — выполнено

По разрешению пользователя:
- Удалены `profile/sources.json`, `audit_sources` и зависимость от хешей/наличия
  team CLAUDE/AGENTS/workflow. Изменения этих файлов не блокируют запуск.
- Launcher проверяет наличие `project.md`, `areas.md`, `testing.md`, но в system
  prompt по-прежнему добавляет только project + personal context. Автоматическая
  загрузка team context по-прежнему отключена.
- `--check` сообщает `profile_files` вместо фиктивного `source_audit: passed`.
- Тесты создают профиль без manifest, проверяют независимость от изменения,
  появления и удаления team instructions, ошибки при отсутствии каждого файла
  профиля и вывод check без запуска Pi. README обновлён под новую модель.
- Skills/roles не реорганизованы; оставшиеся в них procedural ссылки — отдельный
  scope. `checkpoint.md` остаётся необязательным шаблоном, не required context.

Проверки после этой правки:
- Launcher Python unittest — 11 tests OK.
- Runner Python unittest — 13 tests OK (temp fixtures/stubs, без моделей/стендов).
- `node files/pi-ruclaw/tests/runtime-smoke.mjs` — PASS.
- `python3 files/pi-ruclaw/launch.py --check` — PASS на настоящем checkout,
  без direnv execution/LLM; `project_context_autoload: false`.
- Pyright для launcher/tests — без диагностик; Markdown LSP не настроен.
- `git diff --check` — OK для tracked changes; отдельно изменяемые untracked
  файлы проверены загрузкой/тестами. Коммит не создавался.

## Сверка skills и ролей с новым профилем

По просьбе пользователя прочитаны все 8 SKILL.md, executor contract и обе роли.
В рабочем дереве уже были изменения skills/scripts от предыдущей работы;
они не откатывались. Выполнена точечная сверка, без изменения helper CLI и
без сетевых запросов в Jira/GitLab.

Исправления:
- Убраны обязательное чтение workflow/AGENTS/CONTEXT и утверждения об
  «audited baseline» / безусловной истинности repo docs. Selective area map,
  актуальная реализация и явно согласованное намерение теперь разделены.
- Grill: небольшие раунды вопросов вместо всего frontier сразу; вопросы про
  решения, не доступные в коде факты. Shared glossary/ADR edits — после approval.
- To-spec: явные acceptance criteria, выбор test seams по риску вместо догмы
  highest seam, draft не одобряется агентом; core business rules + runtime wiring.
- To-tickets: source links/criteria и verification scope/prerequisites на каждый
  срез, полнота покрытия критериев между slices. Сохранены status/path шаблоны.
- Implement: последовательность остаётся в SKILL.md, reference больше не задаёт
  вторую копию этой последовательности. В reference сохранены authority, design,
  check/review safeguards, правила equivalence и evidence.
- Code-review: реальные requirements могут быть explicit user request, не
  обязательно отдельная spec. Draft core не является runtime guard. Подробный
  delta protocol вынесен в `references/follow-up.md`, читать только на follow-up;
  base/head, initial coverage, независимость и readiness gates сохранены.
- Исправлен конфликт read-only reviewer с записью debt: reviewer сообщает,
  основной executor консолидирует. Роль reviewer отдельно оставляет fetch,
  bundle preparation, test execution и project status/debt edits родителю.
- Git skill: ссылки на оба Git/changelog документа, одна MR decision, отсутствие
  co-author; convention не даёт разрешения на rebase/force-push.
- GitLab skill больше не описывает отдельное двухосевое review; отправляет в
  code-review. Убраны повторные большие templates в GitLab/Jira; короткий вывод
  с canonical links. CI traces/MR/Jira text не являются инструкциями.
- Ops читает заменяемую карту testing и проверяет fixed-name cleanup wrappers.
  Inheritance flags, tools и ограничения ролей не менялись.
- Smoke проверяет загрузку всех восьми skills и наличие executor/follow-up refs.

### Предложения следующего уровня

1. Облегчённый exact-ref review для маленьких локальных изменений согласован и
   реализован следующим этапом ниже. Для MR/рискованного/параллельного review
   immutable bundle остаётся обязательным.
2. Пока не реализовано: не превращать grill → spec → tickets в обязательную церемонию для малого fix:
   direct implement уже принимает task/spec. Можно явно описать выбор маршрута,
   а не объединять все skills в один огромный.
3. Пока не менять gates commit/review/push-before-done и default local Docker
   authority. Они остаются процедурной политикой implement, не фактом проекта;
   их упрощение требует отдельного согласования, не маскируется под чистку текста.

Проверки этой правки:
- Offline resource-loader smoke — PASS, включая все 8 skills и ссылки на refs.
- Launcher unittest — 11 tests OK.
- Review bundle/batches regression tests — 8 tests OK, только временные repos.
- `node --check files/pi-ruclaw/tests/runtime-smoke.mjs` — OK.
- Assertion check относительных refs и удаления устаревших context directives — OK.
- `git diff --check` — OK для tracked изменений.
- Markdown LSP отсутствует; JS LSP недоступен (нет typescript-language-server).

Это проверка загрузки/структуры и регрессий helpers, не LLM-эксперимент качества
инструкций. Продуктовые тесты/стенды/модели и Jira/GitLab API не запускались.

## Облегчённый review и поддержка языка проекта

Пользователь одобрил lightweight review и уточнил: `CONTEXT.md` введён специально
как единый язык проекта и должен поддерживаться в актуальном состоянии. Это не
просто необязательная старая документация. Просмотрены его оглавление и стиль
терминов с `_Avoid_`; сам файл RuClaw этой правкой не менялся.

Реализовано:
- `code-review/SKILL.md` теперь выбирает evidence mode по риску полного
  cumulative increment, не только последнего маленького fix.
- Lightweight: маленький связный локальный committed diff, доступные Git objects,
  один reviewer, без критичных security/tenant/identity/approval/durability/
  concurrency/migration/deployment/shared-contract/generated/binary рисков.
  Точные base/head/merge-base, все changed paths и связанные исходники из Git;
  один report, без exported tree/lanes/results.json. Dirty files не считаются head.
- GitLab MR, широкие/рискованные/неясные изменения, parallel/multiple reviewers
  используют bundled mode. Механика вынесена в `references/bundled-review.md`;
  helper scripts и manifest validation не ослаблены.
- Любое расширение риска переводит review в bundled; независимость, полное
  покрытие, проверки, CI и verdict gates одинаковы в обоих режимах. Даже один
  независимый child может читать local SHAs без bundle; self-review не становится
  independent от выбора lightweight.
- Follow-up reference и reviewer role знают оба режима; отчёт сохраняет mode и
  цепочку carried/fresh evidence. Нельзя упростить рискованный initial increment
  до lightweight только потому, что последний delta маленький.
- Grill начинает с релевантных разделов `CONTEXT.md`, использует согласованный
  язык, проверяет новые понятия/синонимы и возвращает согласованные определения
  в этот файл в существующем стиле. При discussion-only/read-only ограничении
  остаётся предложенный delta; нерешённые определения не публикуются как принятые.
- Нет автоматических branches/commits или изменения поведения кода вслед за
  согласованием термина. Glossary отражает смысл, а не доказывает runtime guards;
  legacy code не должен молча переопределять принятый язык. To-spec переносит
  этот язык, не создаёт параллельный словарь.

Проверки этого этапа:
- `node --check` + offline resource-loader smoke — PASS, все 8 skills/роли и refs.
- Bundle/batches helper regression — 8 tests OK; launcher unittest — 11 tests OK.
- Relative refs/Markdown fences assertion check и `git diff --check` — OK.
- Markdown LSP отсутствует; JS LSP недоступен (нет typescript-language-server).

Это не LLM-проверка правильного выбора evidence mode и не ревью кода RuClaw.
Сетевые API, продуктовые стенды и модели не вызывались; коммитов нет.

## Реальная сессия: bounded consumption отчётов

Пользователь сообщил о ~80% контекста в сессии `01a16ad5-c735-71a2-a8fc-155b9de34460`.
JSONL исследован read-only агрегатами, без импорта transcript в рабочий контекст:
- 324 tool calls, в том числе 129 read; текст read results ~675 тыс. символов.
- Первый nonzero model usage ~6,5 тыс. input; последний ~401 тыс. input+cacheRead.
  Накопленные 58 млн tokens не равны текущему контексту; caching не очищает окно.
- Два больших subagents reference чтения ~83 тыс. символов; parent также читал
  полные review/ops reports (~11–24 тыс. символов каждый).
- Важное уточнение ранней гипотезы: subagent result 56 308 символов — это
  `action: guide`, `topic: tool-reference`, НЕ ответ reviewer. Все 5 workflow
  launches уже упоминали file-only; их launch receipts были ~1 тыс. символов.
  Поэтому основная наблюдаемая проблема — последующие bulk reads отчётов и
  широких справочников, а не отсутствие file-only в запусках.

По разрешению пользователя:
- Добавлен `implement/references/delegated-output.md`: parent-side report reading,
  минимальный нужный launch/API context и explicit bounded output contract.
- Reviewer/ops report начинается с `## Summary`, не более 25 строк / 2500 символов;
  дальше именованные Findings/Coverage/Checks/Resources. Findings/gaps overflow
  отмечается количеством и указателем; нельзя скрывать его за лимитом.
- Parent читает header, потом ВСЕ finding IDs/gaps и нужные sections/source/log
  slices; проверяет coverage/readiness/provenance, а не принимает summary на веру.
  Whole report допускается при реальной неоднозначности, не по умолчанию.
- Поддержан runtime-managed file-only: report остаётся в artifact, возвращаются
  references/status; никаких придуманных API fields, нового enforcement extension
  или запуска моделей. Контракт — инструкции, не гарантированный runtime byte cap.
- Implement, executor contract, code-review и обе роли согласованы; smoke знает
  новый reference. Full review/independence/test gates не ослаблены.
- Автоматический checkpoint/compaction не добавлялся. Для текущей длинной сессии:
  ближайшая безопасная граница → актуальный checkpoint → ручной `/compact` →
  сверка Git/children/resources перед продолжением. Не останавливать/перезапускать
  active children и не редактировать JSONL ради снижения context.
- Новые файлы skills не заменяют уже загруженные инструкции старой сессии.
  Для немедленного эффекта пользователь передаёт bounded-reading policy сообщением.

Проверки этого этапа: offline loader smoke и JS syntax check — PASS; launcher
unittest — 11 OK; review helper unittest — 8 OK; relative reference check и
`git diff --check` — OK. Markdown LSP отсутствует, JS LSP binary недоступен.
Это не проверка соблюдения лимита живой моделью; продуктовые стенды/LLM не
запускались, текущая длинная сессия и её JSONL не изменялись.

## Вторая реальная сессия и технические helpers (история, подход заменён ниже)

Сессия `01a16b3c-7e3f-7364-9e59-b080a34a618c` исследована read-only агрегатами:
100 tool calls; input вырос с ~6,6 тыс. до ~201 тыс. tokens. Новые инструкции
были загружены; summary новых reports занимали 12–14 строк / 1414–2085 символов.
Однако чтение первых 28–35 строк захватывало детали, до ~9700 символов.
Два широких filename discovery вызова дали ~98 тыс. символов, снова загрузились
большие guide/reference документы. Стоимость разных по объёму задач напрямую
не сравниваем; контекст по-прежнему растёт от runtime evidence, не только профиля.

Пользователь разрешил техническое исправление перед новой задачей:
- `scripts/report-summary.py` выделяет ТОЛЬКО leading `## Summary` в отдельный
  sibling `*.summary.md`, atomic write, receipt вместо тела. Missing/empty/late/
  oversized summary — exit 2 без тела; нет fallback на первые N строк. Source
  report не меняется, symlink destination отвергается. Старый summary после
  неудачи не использовать; решение по findings/coverage/checks по-прежнему нужно.
- `scripts/context-files.py` — filename-only discovery от явно выбранного root,
  depth/entry/result/output bounds, исключение VCS/deps/cache и symlink traversal.
  Неполнота — явный reason + exit 3; не превращать её в «ничего не найдено».
- `workflows/review.js` и `workflows/ops.js` — обычные workflowScriptPath bodies:
  fresh custom role, managed relative file-only report, точные SHAs, ops authority.
  Возвращают компактную проекцию receipt, не output/results/transcript. Child ok
  не является review verdict; missing report не становится success.
- `implement/references/delegated-launch.md` документирует конкретный API recipe,
  проверку role policy, helper usage и порядок обработки ошибок. Не новый runner.
- Обновлены delegated-output/implement/README и smoke. Добавлены stdlib Python
  helper tests и JS template tests с mocked runs; native installed validator
  проверяет шаблоны без запуска детей. Новых зависимостей нет.

Проверки технической правки:
- Python suite — 22 tests OK (launcher + summary/discovery helpers).
- JS workflow templates — 6 tests OK с mocked runs, без реальных детей/LLM.
- Offline resource loader + установленный native workflow validator — PASS:
  обе роли найдены, оба template body приняты валидатором.
- Review helper regression — 8 tests OK; refs assertion и `git diff --check` — OK.
- Pyright helper/scripts/tests — без диагностик. JS LSP binary недоступен;
  синтаксис/control flow проверены AsyncFunction tests и native validator.

Новых пакетов не установлено, Guix Home не применялся, живые children/стенды/API
не запускались. Helper bounds проверены; успешное применение recipes живой
моделью проверяется на новой задаче. Для fixed recipes проектный reference
заменяет повторное чтение generic API guides; authority/safety skill остаётся.

## Переход к file-backed work cycles v1 — история, пересмотрен ниже

Сессия `01a16b64-d2a1-70f9-8713-64fa9b3feb0a` проверена read-only: 227 calls,
~249 тыс. input+cacheRead в конце. Summary artifacts уже использовались, но большие
subagents guides и детали reports продолжали накапливаться; три grouped workflows
(3+2+2 children) обошлись без наших single-child templates. Пользователь отверг
продолжение борьбы с размером выводов скриптами и утвердил другой подход:
producer сразу пишет short/full answer, parent обрабатывает связанные вопросы,
сохраняет решения отдельно и возвращает рабочий контекст к начальному состоянию.

Реализовано:
- `result-contract.md`: producer напрямую пишет `short.md`, finding files,
  coverage/checks/resources и ссылки на logs; полный индекс всех IDs/gaps, без квот
  и extraction. Результат snapshot-specific и неизменяемый; decisions у parent.
- `work-cycles.md`: authority/work ledger/resources/decision files и cycle manifest;
  один связанный work unit, truthful checks, statuses fixed-awaiting-verification
  vs closed, повторное восстановление по файлам, не по накопленному диалогу.
- `extensions/work-cycles.ts`: явный `ruclaw_next_cycle` после сохранения состояния.
  На следующем запросе Pi context hook заменяет прежнюю переписку bootstrap-ссылкой
  на manifest, оставляя последующие сообщения цикла. Это настоящий reset model
  working context, но НЕ новая session/process: transcript/runner lifecycle остаются.
  Нет compaction, токен-порогов, скрытого scheduler или implementation fanout.
- Boundary хранится custom entry на ACTIVE branch, восстанавливается после reload;
  ветки до boundary/другие sessions не меняются. Вызов только отдельным batch;
  validate task/base/authority/branch/cycle sequence, реальные HEAD/ancestry и
  существование локальных refs. Заявленные active children блокируют переход.
  Реальный resource/child inventory и истинность authority/gates всё ещё обязан
  сверять parent. При missing boundary — только file recovery со STOP/reconcile,
  не скрытый возврат старого контекста или продолжение по догадке.
- Reviewer/ops получили write только для явно выделенных result/ops artifacts;
  source read-only, запреты Git/test/remote/nested делегации reviewer сохранены.
- Launcher явно подключает extension. Implement/code-review/executor/follow-up/
  checkpoint/README/runner docs переведены на новый контракт. Обычный Pi не менялся.
- Удалены summary extractor, bounded discovery helper, оба single-child workflow
  template, delegated-output/delegated-launch references и их прежние тесты.
  Исторические reports/sessions и сторонние uncommitted изменения не удалялись.

Проверки текущей правки:
- 12 launcher tests, 9 work-cycle tests, 8 review-helper regression tests,
  13 runner Python tests и 3 runner finish tests — все 45 OK.
- Offline native resource loader — PASS, включая загрузку cycle extension и
  обеих ролей с новым short/detail contract. Реальный ExtensionRunner.emitContext
  сохраняет initial/system tool state и последующие user decisions, исключая
  old-context canary. Это проверка SDK transform, не вызов модели/provider.
- Проверены resume/active-branch isolation, второй cycle, reused tool IDs,
  missing boundary recovery, отдельный batch, abort без записи boundary,
  local-path/symlink guards, HEAD/branch/base ancestry, sequence и active-children
  declaration. Механические проверки не доказывают истинность сохранённого state.
- `launch.py --check`, references/legacy-removal assertions и `git diff --check` OK.
  Pyright launcher/tests без диагностик; JS/TS LSP binary отсутствует, Markdown
  LSP не настроен. Native extension loading и Node runtime tests прошли.

Живые LLM/стенды/продуктовые API и Guix Home activation не запускались; поведение
модели и взаимодействие с прочими пользовательскими extensions требуют новой
задачи после активации обновлённого профиля. Продуктовый репозиторий не изменялся.

## Phase-based recovery v2 — действующий основной профиль

Пользователь предоставил сессию `01a16d3e-115f-7579-9777-e8bf03471dca`.
Read-only анализ на момент среза: ~3 ч 16 мин, 1605 calls, 32 успешных boundaries,
максимум ~92 тыс. input+cacheRead, после каждого reset ~5603. Сброс работает,
но subagents_enable/subagent не вызывались. Во всех 32 manifests один HEAD;
формальный committed review ещё не начался, реализация продолжает расширяться.
802 read, 412 bash; 125 команд содержат go test (не число фактических test cases).

Причина регрессии в нашем протоколе:
- Bootstrap сам требовал implement onboarding после каждого micro-slice: implement
  и три contracts читались по 32–33 раза, ~885 тыс. символов только этих повторов.
- state.md/resources.md превратились в журналы (~66/34 тыс. символов на момент
  чтения); один Frontier ~27 тыс. Текущая навигация смешалась с historical evidence.
- Свежий контекст экономит размер запроса, но сам по себе не уменьшает повторную
  работу, serial test/research effort или стоимость. Задачи разные; сравнение
  cumulative session bill не является доказательством ускорения/замедления.

Пользователь разрешил исправить подход и запросил безопасное продолжение текущей
сессии. Перед изменениями рекомендовано старому исполнителю закончить текущую
команду, сохранить компактный work/resume.md с исходным base/HEAD/dirty work/
незавершёнными gates/current resources и остановиться без нового cycle/done.
Из этой сессии не посылались команды старому Pi и не менялись его продуктовые файлы.

Изменения v2:
- `resume.md` — отдельный короткий entry point; не читать все policies, task history
  и все results по умолчанию. Restore compact current index/authority + live
  inventory, только phase-relevant short/detail files, проверка provenance/inputs.
- Фазы implement -> review -> fix/review -> verify -> publish. Ранний независимый
  review coherent committed increment до дальнейшего расширения большой задачи;
  промежуточный review не выдаётся за готовность всех критериев/MR. Изолированный
  ops для тяжёлых gates, возможна concurrency в фазе на immutable inputs.
- Bootstrap больше не требует implement/трёх contracts и micro-step/reset loop;
  явно указывает resume entry point, destination phase и запуск review в review.
- v2 manifest требует phase, transition/reason/evidence. Same-phase micro reset
  отвергается; explicit recovery с evidence допускается без вынужденного commit.
  short_answers может быть пустым до review: не создавать искусственный self-report.
- v1 manifests не удаляются, новые transitions по ним отвергаются с инструкцией
  разовой миграции. Persisted v1 boundary восстанавливается через новый resume
  entry point; original task/base/authority/branch и cycle sequence сохраняются.
- current.md — заменяемый frontier + ссылки, issue/gate indexes сохраняют все IDs;
  history/commands/proofs отдельно. resources — current live/retained inventory,
  не дневник прошлых прогонов. Legacy большие файлы остаются evidence.
- Actual HEAD/ancestry/path checks, call-alone/abort, active-branch persistence,
  no-active-child declaration и все acceptance/publication/cleanup gates сохранены.
  Никаких новых output quotas, implementation fanout или фонового scheduler.

Проверки v2:
- 12 launcher + 12 cycle + 8 review-helper + 13 runner Python + 3 finish tests:
  все 48 OK. Cycle tests покрывают phase transition, same-phase rejection/recovery,
  legacy migration с сохранением task/base, empty pre-review results, а также прежние
  path/Git/sequence/abort/batch/resume/branch-isolation guards.
- Native SDK resource loader и ExtensionRunner.emitContext PASS: реальный resume
  path существует и указывает в текущий профиль, destination phase сохранён,
  old-context исключён, system/tools/new user decisions остаются. Bootstrap больше
  не требует implement onboarding/всех results; subagents_enable явно указан.
- launch.py --check, recovery reference assertions, git diff --check OK.
  TS/JS LSP binary отсутствует, Markdown LSP не настроен; Node/native loader tests
  не заменяют typecheck или live LLM behavioral validation.
Guix Home не применялся, продуктовые файлы/стенды не менялись; реальный model
behavior, компактность frontier и своевременный review требуют живого продолжения.
Истинность phase evidence и реальный inventory по-прежнему проверяет исполнитель,
а не schema validator. Обещания ускорения только по offline tests нет.

## T15R38-G01 — single-output override vs short/detail (исправление контракта)

Пользователь сообщил: independent delta review `945aad6c8` завершён, но output
protocol заблокировал фазу fix. Read-only проверены current.md и установленный
pi-subagents `src/runs/shared/single-output.js` / child-launch-plan.js. При заданном
output-path runtime действительно инжектирует в system+task authoritative path и
«Ignore any other output filename or output path ...». Наше прежнее утверждение,
что file-only binding можно оставить для receipt, а детали писать отдельно, было
неверно. Это конфликт наших launch instructions, не продуктовый дефект и не
основание повторять уже выполненное source review.

Исправление:
- Reviewer/ops defaults `output:false`, `outputMode:inline`. Parent явно применяет
  тот же режим ко всем child items. Inline только completion status/paths, не
  findings/logs. Сам producer пишет short/detail в назначенный каталог, как и было
  согласовано. Не менять глобальный pi-subagents и не обходить runtime instructions.
- Уточнены result-contract/implement/resume/README; file-only receipt исключён для
  multi-file результата. Native planner + prompt injector проверяются на реальных
  exports без запуска child; отрицательный контроль сохраняет демонстрацию конфликта.
- Existing authoritative single-file review разрешён как историческое independent
  evidence: parent-authored navigation-only index с ссылкой на producer/run/SHA/
  sections, без приписывания себя reviewer и без выдуманных coverage/checks. Если
  содержание достаточно, format-only blocker можно закрыть; содержательные gaps
  остаются открытыми. Никакой повторной оценки исходников ради перепаковки.
- Для текущей сессии достаточно явного user protocol amendment, restart не нужен;
  будущие launches задают output:false/inline даже при ещё старом role store-path.
  Все prior readiness gates, acceptance/push/deployment restrictions неизменны.

Проверки исправления: 12 launcher + 12 cycles + 8 review-helper tests OK (32).
Native runtime smoke PASS: defaults ОБЕИХ ролей и явные overrides false/inline
дают outputPath undefined, не инжектируют system/task single-path instruction;
negative control с receipt/file-only воспроизводит конфликт. Recipe из самого
result-contract.md принят installed workflow validator. git diff --check OK.
JS/TS LSP binary отсутствует; live multi-file LLM compliance не проверялось.
Продуктовые файлы/current state не изменялись, действующим агентам ничего не
отправлялось; глобальный pi-subagents/Guix Home не менялись.

## Отдельный Lite pilot — не замена текущего профиля

Пользователь одобрил отдельный профиль и сравнение на другой ветке. Текущий
fix-run `01a16edb-ee63-7152-9ed6-3a1401d413f2` исследован read-only: исходный
запрос — исправить .scratch/RCL-821/extern_review.md, 9 замечаний внешнего MR622
review. На срезе17:52 ~51мин/9 boundaries; fix+review получили три IDs, шесть
остальных ещё открыты. Это не доказательство скорости нового подхода; отдельно
учитывать качество/одинаковый endpoint и активное время vs human/test waits.

Создан opt-in `lab/` под существующим recursive profile:
- Shared project/areas/testing/personal context прежние. Отдельные policy + два
  коротких lite-spec/lite-implement skills, prompt /lite-review, один fixed native
  workflowScriptPath, fresh independent ruclaw-lite-reviewer. Main builder остаётся
  единственным source writer, source/acceptance независимость и exact refs сохранены.
- Нет cycle extension/обязательных resets/phase manifests, generic API-guide skill
  не подключается. Native compaction/settings не менялись. Сначала coherent batch
  fixes+focused checks, потом review; critical pass по риску, не формальный whole
  review каждого finding. Producer short/details, output:false/inline, compact receipt.
- Это OpenSpec-inspired артефакты/сценарии, НЕ установка OpenSpec CLI. Named operation
  использует уже установленный native pi-subagents, без добавления registry package.
  Не ставились third-party пакеты; не модифицировались global settings/auth/extensions.
- Launcher требует отдельный linked worktree того же repo и experiment/pi-lite-*
  branch, отказывает main/другим repo/обычным branches. Личные инструкции берёт как
  baseline. Primary direnv только для credentials; cwd и PI profile env явно
  восстанавливаются ПОСЛЕ direnv. Никакого .envrc copy или env dump.
- No push/MR/deploy без отдельной authority. Local commits/private disposable PG
  разрешаются только реальным пользовательским launch request, не profile-файлом.
  Старые host socket/network/firewall/stand-delete permissions НЕ наследуются.

Подготовлен реальный worktree (по явному запросу пользователя, без запуска LLM):
- path: /home/dyens/dev/croc/worktrees/ruclaw/pi-lite-RCL-821-extern-review
- branch: experiment/pi-lite-RCL-821-extern-review
- base: 2cbf24589788b7c27d364b824c53b3f8d13ca675 — ровно исходный reviewed candidate,
  не текущий main HEAD с готовыми исправлениями. Основной checkout не переключался.
- Frozen 20 input MD files,70863 bytes: исходный extern_review и original review
  indexes/findings/gaps. SHA256/provenance в .scratch/pi-lite/comparison.json.
  Extern request побайтово по тексту совпал с первым read исходной fix-сессии.
  Builder solutions/history/current state старого исполнителя не копировались.
- Baseline provider/model/effort записаны из header: openai-codex/gpt-6.1-sol/medium.
  LFS checkout с SKIP_SMUDGE=1: pointers не объявлять media validation.
  Рабочее дерево clean; evidence в ignored scratch. Никаких реальных commits,
  push, product tests, Docker/DB operations или вмешательства в текущую сессию.
- Worktree НЕ изолирует host Docker/DB/сеть/caches; обязательны собственные approved
  backend IDs/ports/roles. Shared caches/host contention ограничивают честность timing.

Alias pi-ruclaw-lite добавлен в home/base.scm; старые aliases/launcher/runner не
менялись. Старый alias regression test расширен на третью opt-in команду. README
содержит check/start без homerec, точный model/effort и proposed user permissions.
Проверки pilot:
- 7 Lite launcher tests + 5 named-workflow control-flow tests PASS.
- Native Lite resource-loader/validator smoke PASS: ровно два Lite skills, named
  prompt, native subagent tools, fresh isolated reviewer/false-inline; нет cycle
  tool, team context или generic technical skill. Standalone loader не является
  подтверждённым live Pi host: native runtime ожидаемо сообщает eager fallback
  subagent вместо lazy subagents_enable; smoke допускает оба поддерживаемых режима.
- Existing regressions: 12 launcher + 12 cycles + 8 review-helper + 13 runner Python
  + 3 finish =48 PASS. Всего60 tests и оба native resource-loader smoke PASS.
- Real experimental launch.py --check PASS; original base/branch и clean tree
  проверены. После direnv восстанавливаются cwd и PI profile env, LD удаляется.
  Проверка не создаёт metadata/bytecode в profile source; live run пишет только
  диагностический starting-head/paths receipt в собственный ignored scratch.
- git diff --check OK, Pyright новых launcher/tests и старого alias test без
  диагностик. TS/JS LSP unavailable, Markdown/Scheme LSP не настроены; native JS
  compilation/runtime tests прошли. Guix Home build/activation не запускались.
Новый agent автоматически НЕ запускался. Local product commits, tests/stand ops,
remote APIs и package installs при подготовке не выполнялись (только Git fixtures
в offline tests). Качество/скорость и соблюдение policy живой моделью не проверены.

## Live pilot и проверка качества результата

Пользователь запустил Lite, session 01a16f89-9379-705e-bf98-df1ec91afbf5. Реальный
первый user message21:23:41, final21:55:04 (~31мин23с), не header20:10. Same
openai-codex/gpt-6.1-sol/medium. Parent278 calls,0 reset,2 named review workflows
(initial+delta, каждый primary+critical). Session Info $3.866/26.49M tokens — это
не удостоверенная all-agent стоимость. Последний контекст223k; профиль уменьшил
повторы, а не гарантировал маленькие запросы.

Candidate8e879041 (initial95ee06e7). Producer и оба reviewer объявили source endpoint
по9 IDs завершённым, сохранив live E2E/combined PG-OAuth-grant/CI gates. По запросу
пользователя сделана отдельная read-only проверка качества с original criteria и
consumers вне diff. Подробности: [quality audit](lab/evaluations/RCL-821-quality.md).
Lite frozen20 files SHA256 unchanged, HEAD/clean tree перепроверены. Основной
сравниваемый SHA a9b5de71 — промежуточный, не финальный результат другого агента.

Найдены конкретные проблемы Lite:
- Q1/RUNTIME-F04: finalize_attachments меняет collector до after_tool; отказ
  acceptance не очищает выбранные IDs, terminal selection всё ещё использует их.
  В основном SHA есть deferred markFailed и blocked-selection regression.
- Q2/RUNTIME-F03: ingestion budget только raw bytes; не учтены base64/envelope и
  stream1MiB vs fallback64MiB. Уже1MiB raw даёт~1.4MiB frame и может потерять весь
  Message вместо local file_error. В основном SHA есть messageFileBudget/HTTP tests.
- Q3/RUNTIME-F02: bridge есть, но non-streaming polling сначала полностью b.Wait,
  затем yield snapshot. Lite gated test проверяет send/observing, не wait/polling.
  Основной SHA содержит poll observer и gated wait tests.
- При этом Lite source впереди этого основного среза по DELIVERY-F02/F03. Нет
  основания объявлять одну ветку целиком лучшей или профили равноценными.

Это source counterexamples, не новый live прогон. Проверен JSON PASS для ключевых
Lite позитивных tests; их узкий scope не доказывает отрицательные сценарии.
Stdlib расчёт encoded frame выполнен, product code/tests/стенды/Git не запускались
и не изменялись. Предыдущий ответ «все9 исправлены» был слишком уверен: source
review verdict/49-of49 paths не равен доказательству acceptance invariants.

## Общие runtime probes — выполнены по запросу пользователя

Пользователь одобрил ближайший шаг2: проверить три counterexamples на обоих pinned
SHA, без Docker/изменений основного checkout. Созданы lab/evaluations/probes/*.go
и stdlib Python run-quality-probes.py. Git archive каждого immutable SHA экспортирован
в отдельные /tmp directories; те же probes добавлены ТОЛЬКО в экспорты. Ни один
product worktree, ref или source file не менялся. Исходные SHA остались прежними.

Два прогона согласованы. Canonical run: /tmp/pi-ruclaw-quality-20261024-b;
results.json и полные JSONL скопированы в lab/evaluations/results/2026-10-24/.
Go1.27.1/goolm/CGO0, -mod=readonly, GOWORK/GOENV/GOPROXY off, пустой HOME,
allowlisted env без DSN/stand/model credentials. Кеши Go общие; тайминги не benchmark.
HTTP — новые loopback fixtures, TLS — новые ephemeral ports на private interface
через существующий testinfra (НЕ loopback; hostname resolution), автоматически
закрытые cleanup. Не Docker/PG stand и не ОС sandbox. No LFS/media validation.

Результаты,13 leaf cases на каждом SHA (15 records с parent groups),SKIP0:
- Lite9 PASS/4 FAIL, все три группы различают кандидатов.
- Основнойa9b5de71:13 PASS/0 FAIL.
- Q1: allow/intermediate PASS в обеих; deny в Lite сохраняет final attachment ID.
  Проверка actual Loop/finalizer/after_tool с mock DocumentStore, не весь A2A→UI.
- Q2: direct16B/750KiB/1MiB и streaming16B/750KiB PASS в обеих. 1MiB в fallback
  и partner SSE возвращают outcome_unknown вместо Message в Lite; основной
  сохраняет text+local file_error. Actual private HTTP writer/client и TLS GET.
- Q3: working snapshot удержан во время gated second GET в Lite, до release
  приходит в основном. Barrier-based порядок, не произвольный latency sleep.
- Новый envelope fixture всегда пишет actual body. Старый основной overflow test
  не писал body и мог проверять EOF, а не base64 budget; эта слабость не перенесена.
  Поэтому наличие старого теста само по себе не считалось доказательством.
- Финальный runner13.04с Lite/13.54с основной; без новых model/API calls. Exit1
  runner ожидаем из-за настоящих regression failures, coverage_ok=true для обеих.
- Проверено, что output запрещён в основном И linked worktree, без создания файлов.
  Pyright runner clean; gopls probes в config не имеет module root, оба реальных
  source-package compile/run прошли. Полные acceptance/CI/race не выполнялись.

Обновлены quality report, evaluation README и plan. Конкретные три проблемы теперь
подтверждены выполнением, не только source reasoning. Это targeted cases, а не
процент общего качества профиля/продукта. Правки Lite, публикация и остановка
другой сессии этим шагом не выполнялись.

## Lite v2 — исправляем процесс, не вручную продукт

Пользователь остановил ручное исправление Q1/Q2/Q3: задача — проверить улучшенный
процесс на повторном чистом запуске. Новых product commits/checks в прерванной
попытке не было. Шесть modified и четыре новых файла моей незавершённой правки
сохранены с полными bytes/SHA256 и binary patch в
/home/dyens/vms/guix-config/.scratch/pi-lite-aborted-repair-gx47cqpn.
После проверки точного списка/HEAD восстановлены ТОЛЬКО эти6 tracked files из8e,
удалены ТОЛЬКО эти4 совпавших с backup added files. Старый experiment worktree
снова clean на8e879041; его два коммита и результаты первого пилота сохранены.
Никаких reset --hard/clean/stash/переключений основной feature-ветки.

Создан новый worktree:
- /home/dyens/dev/croc/worktrees/ruclaw/pi-lite-v2-RCL-821-extern-review
- branch experiment/pi-lite-v2-RCL-821-extern-review
- HEAD2cbf24589788b7c27d364b824c53b3f8d13ca675, clean.
- Скопированы только те же20 frozen input files с прежними SHA256 и новый
  comparison.json с profile_revision=lite-v2-scenario-evaluation. Нет готовых fixes,
  probe tests, previous run logs/decisions. LFS smudge по-прежнему пропущен.

Изменение процесса небольшое, но функциональное:
- Builder до реализации связывает original ID→наблюдаемое поведение→реальную
  boundary→различающую регрессию. Это существующий компактный result index, не журнал.
- Workflow теперь source reviewer + НОВЫЙ независимый behavioral evaluator, вместо
  второго source-only critical pass. Для данной risk-task остаётся2 children,
  не добавлен третий. critical=true фокусирует оба на критических цепочках.
- Evaluator сначала выводит scenarios из original criteria, затем проверяет
  implementation/assertions и может запускать local probes в собственных immutable
  exports. Нельзя менять live checkout, делать product fixes, nested fanout,
  Docker/DB/stand/remote operations. Без inherited credentials/DSN, с проверенными
  helpers и явной фиксацией реальных bindings/cleanup. Это не OS sandbox.
- Положительный source review не закрывает behavioral criterion. По каждому ID
  отдельно source disposition и proven/partial/unverified/contradicted. Частичная
  проверка/иной action/mock/PASS names не маскируют исходный сценарий.
- Нельзя читать предыдущие решения/сессии/sibling attempts/lab/evaluations как
  oracle. Наши13 post-hoc probes остаются внешним holdout, не скопированы builder.
- Сохраняются continuous builder, native compaction, multi-file false/inline,
  единый review batch и affected-invariant follow-up. Нет нового phase/reset
  протокола, пакетов, автопубликации или нового E2E platform requirement.

Изменены lab policy/implement/reviewer, добавлен agents/lite-evaluator.md, обновлены
named workflow/prompt, README, launcher required roles/revision и focused tests.
Проверки:8 launcher +6 workflow +12 existing launcher tests PASS; оба native SDK
smoke PASS. Native discover/planChildLaunch/validator подтвердили обе fresh роли,
false/inline и неизменённый старый профиль. Missing evaluator receipt не означает
success. Real launch.py --check нового worktree PASS. Pyright clean; TS LSP binary
отсутствует, Markdown LSP не настроен; JS проверен native validator/runtime tests.
Реальная модель/evaluation/product tests, homerec и package installs не запускались.
Само качество/стоимость v2 ещё предстоит измерить; это не доказано offline tests.

## V2 завершён; внешние holdouts всё ещё FAIL

Пользователь прислал session01a17045-e0b8-7006-bc8c-6e239f4aa97e. Actual model
openai-codex/gpt-6.1-sol/medium. User23:37:02→final00:19:54 (~42мин52с), parent272
calls/$4.334/30.38M tokens,0 reset,3 review rounds (6 child passes). Parent bill не
all-agent cost. Против первого Lite31мин23с/$3.866 — дольше~37%, дороже~12%; не
контролируемый benchmark. Candidate d5189d42, clean;20 input hashes unchanged.

Проверен результат, initial/final evaluator criteria/checks и внешний неизменённый
holdout в отдельном immutable export:13 cases,9 PASS/4 FAIL,SKIP0,coverage_ok=true.
Те же3 проблемы повторены: after_tool deny оставляет FinalAttachmentIDs;1MiB URL
в fallback/SSE теряет Message с outcome_unknown; polling working withheld до release.
Положительные controls PASS. Старыйa9b5de71 ранее проходил те же13 cases. Исходные
checkout не менялись, Docker/PG/модель не запускались; только собственные ephemeral
HTTP/TLS fixtures, sanitized env, cached Go. Подробности/логи/границы:
[Lite-v2 outcome](lab/evaluations/RCL-821-lite-v2-outcome.md).

Полезный эффект v2: честнее proven/partial/unverified, самостоятельные wire probes,
исправлены MIME и escaped-ID случаи. Но улучшения на этих измеренных3 сценариях нет.
Evaluator спутал projection-denied с after_tool final selection; polling seam
подменил producer/UI checks; private-interface URL test отказался выполнять как
вне authority, хотя actual user HTTP/TLS grants были. Fresh workflow не передаёт
точный per-run grant scope; это вероятная handoff-проблема, не разрешение ослабить
безопасность. Общий запрет remote actions и отсутствие stand не заменяют analysis
собственных local fixtures. Новых profile/code changes по одному Session Info нет.

## Acceptance-first процесс — реализован, live эксперимент не запускался

Пользователь одобрил перенос независимой подготовки приёмки ДО реализации,
проверку минимальной реальной boundary, явную authority и два отдельных результата.
Новый profile_revision: lite-v3-acceptance-first. Это не третий запуск RCL-821.

Изменено только lab/ и plan:
- Новый /lite-acceptance → workflows/prepare.js: один existing evaluator в режиме
  PREPARE, только original base/request и отдельный current authority record.
  Candidate/fix-history в задачу не передаётся. Parent не пишет product source,
  пока не просмотрены criteria/probes/positive-negative controls/baseline evidence.
- Authority record цитирует реальные текущие user grants/restrictions и источник
  сообщения, перечисляет writable dirs/commands/fixture bindings и запреты.
  Private interface не путается с loopback; role ceilings/поздние user revocations
  сохраняются. Файл сам по себе не создаёт полномочий.
- Evaluator готовит suite/criteria.json (все approved IDs, requirement/delivery,
  observable boundary, cases/status/reason/evidence), authority.md, run.md, probes
  и baseline logs. Только base exports; никакого implementation worker, stand
  платформы, candidate-driven выбора удобных проверок или нового oracle.
- Parent проверяет семантику/покрытие и фиксирует согласованный suite до coding.
  scripts/acceptance.py freeze создаёт новый seal вне suite, печатает SHA256 anchor.
  Fingerprint всех файлов, включая assertions/authority; existing seal не overwrite.
  verify проверяет ИСХОДНЫЙ anchor/base, полный набор файлов, запрет symlinks,
  добавлений/удалений/подмены; optional --suite проверяет точную execution copy.
  Это фиксация ТЕСТОВОГО контракта, не возвращение source-currency hash launch gate.
- После coherent builder batch /lite-review требует seal+original anchor и явно
  передаёт frozen authority обеим fresh ролям. Source reviewer остаётся read-only;
  evaluator в режиме VERIFY повторяет старый suite в exports, не придумывает новый
  subset. Нельзя ослаблять assertions/tiers; ошибочный контракт требует явного
  решения, нового seal/anchor и сохранения старого evidence.
- results.json перечисляет ВСЕ case IDs/candidate/original anchor/status/evidence.
  acceptance.py judge отклоняет missing/duplicate/unknown cases, другой candidate/
  anchor, недопустимое evidence. Любой required fail/skip/blocked → not_met;
  зелёное подмножество не принимается. Delivery checks отдельно; production_readiness
  всегда not_established этим инструментом, даже при pass всех объявленных checks.
- Набор ролей прежний: source reviewer и evaluator; PREPARE добавляет отдельный
  ранний вызов того же evaluator. Это реальная дополнительная стоимость, не обещание
  экономии. Нет нового context reset/phase journal/extension/package/autopublication.

Проверки:25 lab Python (17 contract +8 launcher),9 workflow JS,12 old launcher =46
PASS; оба native SDK smoke PASS (оба prompt/recipe, fresh roles, false/inline,
отсутствие cycle tool, неизменённый основной профиль). Отдельный synthetic CLI smoke
freeze→verify→judge и отказ blocked/tamper PASS. Реальная --check загрузка профиля
PASS без запуска модели. Pyright новых Python clean; TS LSP отсутствует, Markdown
LSP не настроен; JS реально прошёл native validator и control-flow tests.
git diff --check OK. Actual RuClaw checkouts не менялись, новых branches/commits,
product tests, Docker/PG/remote/model calls и homerec в этом шаге нет.

Ограничения: hashes не доказывают качество тестов/истинность grants/честность логов;
judge агрегирует заявленные результаты, не выполняет тесты и не подтверждает их
семантику. Это не OS sandbox и не блокировка для агента, сознательно нарушающего
протокол. Parent должен сверять original IDs/реальные assertions и удерживать
исходный anchor. Реальные acceptance suites для новой задачи ещё не подготовлены;
все проверки этого изменения были offline/synthetic, не новая приёмка продукта.

## RCL-808 — выбран следующий intake, scope ещё уточняется

Пользователь выбрал RCL-808. Прочитана Jira helper: Backlog, заголовок про не
останавливающиеся polling goroutines после tenant deletion (проверено TG), description
отсутствует, comments0. Нельзя считать критерии уже утверждёнными из одного заголовка.
[Draft intake](lab/evaluations/RCL-808-intake.md): soft-delete vs purge, общий lifecycle
vs Telegram/test teardown, текущая develop base и точные local fixture permissions.
Предложенные outcomes отделены от approved intent. Проверка канала Channel.Delete
не заменяет tenant deletion; inbound-deny не доказывает остановку самого poller.
Текущий RuClaw checkout не менялся, fetch/worktree creation/evaluator/tests/source
implementation не запускались. Jira GET TLS верифицировалась с системным CA bundle,
не через insecure bypass. Следующий шаг — короткое согласование существенного scope,
после него подготовка независимого suite на original base, до реализации.

## Следующий шаг

Согласовать scope/authority/base RCL-808, затем только подготовку приёмки (/lite-acceptance), без
product edits. Просмотреть качество cases/границы/базовые failure reasons ДО
реализации, затем согласовать freeze. Не запускать автоматически третий повтор
уже известного RCL-821 и не переносить старые post-hoc holdouts как готовое решение.
Измерять полную стоимость prep+builder+source review+replay, misses/false positives
и честность финальных verdicts. V2 не объявлять победителем, acceptance-first
улучшением качества до нового живого измерения тоже не объявлять. Live corpus
только на отдельно одобренном owned stand. Publication/production readiness
по-прежнему не разрешены результатом настройки harness.
Текущий профиль/format amendment остаётся действующим для старых запусков.
После реорганизации тестов переаудировать testing.md и заменить entry points
реальным scope dispatcher.

Оставшиеся gaps: knowledge/documents/artifacts ACL, broker prefix/cache isolation,
все delegated/recovery пути, полный перечень MCP/прочих sidecars, deployment и
CI/test conditions. Это адресные будущие проверки, не обещание готовности
продукта и не блокировка компактного описания архитектуры.
