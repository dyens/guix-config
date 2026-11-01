# RCL-808 — intake, НЕ утверждённый приёмочный контракт

Источник: https://jira.croc.ru/browse/RCL-808, прочитан Jira helper через GET.
Заголовок: «Тесты по каналам при удалении тенанта не останавливают горутины для
поллинга (проверено на ТГ)». Backlog, priority3, assignee Александр Капустин.
Description отсутствует, comments0. Сам заголовок не задаёт точный lifecycle/SLA.
Jira не изменялась; TLS verification сохранена, для helper использован системный
CA bundle /etc/pki/tls/certs/ca-bundle.crt после ошибки default trust store.

Пользователь выбрал задачу для acceptance-first pilot: подготовка приёмки без
реализации. Не копировать решения/holdouts RCL-821. Продуктовый checkout clean,
активная feature/RCL-821 не переключалась; branch RCL-808 локально не найдена.
Локальные refs: develop eed5aa9d4 (2026-10-21), origin/develop f4ada6881 (2026-10-22).
Не зафиксирована свежесть origin/develop; fetch и выбор нового base не выполнялись.

## Материальные уточнения до подготовки исполняемого suite

1. Речь об остановке уже при soft DELETE tenant либо только при физическом purge?
   Рекомендация: soft deletion инициирует остановку; ожидание завершения учитывать
   отдельно от HTTP acceptance, не придумывать синхронность/численный SLA.
2. Scope: общий lifecycle channel instances с Telegram как обязательным первым
   репродуктором, либо строго Telegram/test teardown? Не включать автоматически
   новую E2E matrix всех adapters только из слова «каналы».
3. Подтвердить baseline из актуального develop и authority подготовки: читать/
   экспортировать source, писать probes/evidence только вне product source;
   собственные ephemeral HTTP/TLS fixtures с явными bindings. Никаких реальных
   Telegram calls, Docker/PG/shared stand, commits, push или реализации по умолчанию.

## Предлагаемые наблюдаемые outcomes (ещё НЕ approved)

- После согласованного tenant deletion lifecycle активный Telegram polling request
  отменён и владеющая им goroutine завершена; одного запрета обработки inbound мало.
- После drain не появляются новые polls для удалённого tenant/channel.
- Другой живой tenant продолжает polling; нет global shutdown.
- Повторная reconciliation не возрождает deleted tenant instances.

Не заменять tenant deletion прямым Channel.Delete/Stop или удалением fake server:
так тест может сам выполнить требуемую остановку. Global runtime.NumGoroutine и
случайный sleep сами по себе не доказывают завершение конкретного poller.

Релевантные исходные seams для будущего evaluator (исследованы read-only в текущем
checkout, не утверждение о корректности/корневой причине): channels/reconciler.go,
channels/telegram/channel.go, channels/tenant_liveness_test.go,
cmd/gateway_channel_invalidation.go, tests/dsl/tenant.go, channel_instances.go,
tests/e2e/channel/telegram/channel_delete_test.go. Последний проверяет удаление
самого channel, что не является приёмкой tenant deletion.

Новый worktree/suite/seal не созданы, evaluator/model не запускался, продуктовые
тесты/стенды и исправления не выполнялись. Сначала согласовать scope/authority/base.
