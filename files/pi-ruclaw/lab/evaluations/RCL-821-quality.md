# RCL-821: Lite vs основной профиль — read-only оценка качества

## Зафиксированные кандидаты и границы

- Общий fix-base: `2cbf24589788b7c27d364b824c53b3f8d13ca675`.
- Lite: `8e8790416963fd8185df0aa40b7746badad8474a`, worktree
  `/home/dyens/dev/croc/worktrees/ruclaw/pi-lite-RCL-821-extern-review`.
- Основной исполнитель: `a9b5de71b3ecbe2c718313501177fc475c0070a1` — зафиксированный
  промежуточный срез, НЕ его финальный результат. История могла продолжиться.
- Контракт: frozen `.scratch/RCL-821/extern_review.md` и отдельные original findings.
  Исходные 20 файлов Lite сверены SHA256, не изменены; HEAD/clean tree сверены.

Первый этап — отдельная проверка исходников и валидности доказательств, а не
пересказ самоотчётов и не полный security/acceptance-аудит. Изучены соответствующие
diff, consumers вне diff, новые тесты и часть execution artifacts. На первом этапе
product tests не выполнялись. Затем пользователь одобрил три целевые регрессии:
они запущены на экспортированных snapshot, результаты ниже. Рабочие checkout,
ветки, Docker/PG-стенды, push/MR не изменялись.

**Вывод:** утверждение «Lite всё починил» не подтверждается. Найдены два конкретных
остаточных дефекта и дополнительный непокрытый polling-вариант. В этих сценариях
основной кандидат содержит более полное исправление и регрессии. При этом Lite
реализовал DELIVERY-F02/F03, которых в данном основном срезе ещё нет. Из одного
пилота нельзя вывести общий рейтинг профилей или эквивалентность качества.

## Q1 — RUNTIME-F04: after-tool deny не отменяет выбор вложений

Блокирующее несоответствие исходному требованию «denied-after-tool/reset не
доставляют файл». Это существующая слабость consumer, которую Lite оставил при
подключении A2A к этому consumer, а не доказанная новая регрессия общего finalizer.

Lite source:
- `internal/tools/a2a.go:318–340`: создан document bridge, возвращён document_id.
- `internal/agent/final_attachments.go:171–174`: Execute finalizer сохраняет
  `selected`, `validated`, `failed=false` ДО acceptance результата.
- `internal/agent/loop_tool_acceptance.go:81–83`: after-tool block заменяет только
  Result на ErrorResult; FinalAttachmentCollector не очищается.
- `internal/agent/final_attachments.go:63–76`: validated selection возвращается
  независимо от того, принят ли результат finalize_attachments.
- `internal/agent/loop_terminal_stage.go:330–342`: terminal selection использует
  collector, failedFinalization остаётся false.

Контрпример: успешно получить A2A PDF → вызвать finalize_attachments(document_ids)
→ after_tool guard запрещает именно finalize_attachments → модель завершает ответ.
Collector по-прежнему содержит документ; финальный выбор не отсекает его. Отдельный
запрет after_response мог бы остановить доставку, но не исправляет нарушение
решения after_tool в сценарии, где after_response разрешает обычный ответ.

Тест Lite `TestA2AUserFrontOutputsHaveSelectableDocumentIdentity` подменяет
projector и проверяет положительный bridge/отсутствие auto-selection. Новый live
E2E проверяет положительный выбор/скачивание, но не blocked-selection/reset и не
выполнен. Это не доказательство нужного отрицательного инварианта.

В основном SHA `acceptToolResult` добавляет deferred markFailed для непринятого
finalize_attachments; `TestA2AFinalAttachmentExplicitSelectionAndAcceptance`
содержит отдельный blocked-selection сценарий. Этот тест в рамках аудита НЕ запускался.

## Q2 — RUNTIME-F03: decoded budget не учитывает фактический response envelope

Lite `internal/credbroker/a2abroker/download_projection.go:18–45` выделяет до
MaxDecoded=64MiB, вычитая только len(Raw), и затем помещает скачанные bytes в Raw.
Не учтены base64 expansion, остальные поля/parts и разный бюджет stream/fallback.

- `contract/contracts.go:11–16`: MaxBody=1MiB, MaxWire=64MiB, MaxDecoded=64MiB.
- `a2abroker/stream.go:210–213`: настоящий stream отвергает !fitsResponse(event).
- `server/a2a_stream.go:50–52`: writer прекращает ответ при frame >1MiB.
- Non-streaming JSON также имеет общий потолок 64MiB.

Детерминированный расчёт stdlib Python, БЕЗ запуска product code:
1MiB raw PDF + короткий message/text → JSON stream frame с newline = 1,398,282
байта >1,048,576. 49MiB raw → только base64 =68,506,968 байт >64MiB потолка.
Оба raw-размера допускаются broker ingress budget; default tool PerFile тоже64MiB.

Вместо локального file_error с сохранённым текстом весь результат может превратиться
в protocol/limit error или обрыв (зависит от stream/fallback пути). Это не только
отсутствие E2E: encoded size противоречит неизменённому writer contract.

Lite positive test скачивает строку `%PDF-contextless` и вызывает broker напрямую;
он не проверяет приватный writer на envelope boundary.

В основном SHA добавлены `messageFileBudget(..., streaming)`, точный учёт base64 /
metadata / newline и tests `TestMessageFileBudgetIncludesMetadataRawAndLocalError`,
а также private HTTP tests в `server/a2a_message_files_test.go`. Их выполнение
данным аудитом не удостоверяется; наличие более полного code path установлено.

## Q3 — RUNTIME-F02: не закрыт live progress для polling fallback

Lite правильно добавляет bridge safe progress → external event → owner/call-scoped
snapshot → UI. Однако `a2abroker/stream.go:98` всё ещё сначала блокируется в b.Wait,
и лишь после его возврата yield-ит identity/snapshot. `wait.go:pollTask` удерживает
working/submitted до terminal/input-required/timeout и не имеет observer callback.
Следовательно для non-streaming partner промежуточный working status не дойдёт
до UI во время ожидания. В streaming варианте bridge может работать правильно.

Lite gated progress test (`internal/agent/a2a_external_progress_test.go:18–35`)
проверяет SendStream/observing; WaitStream прямо panic("unexpected wait"). Он не
различает нужный polling/wait дефект. Факт PASS этого теста установлен в packages.json.

В основном SHA polling adapter переведён на pollTaskObserved и отдаёт изменения
до возврата Wait; добавлены poll observer / stream progress tests и gated wait,
не только gated send. Это дополнительное функциональное покрытие исходного
требования статусов ожидания, не утверждение о live browser acceptance.

## Матрица девяти original IDs

«Выглядит исправленным» ниже = source review без найденного здесь контрпримера,
НЕ универсальное доказательство отсутствия дефектов.

| ID | Lite | Основной срез a9b5de71 |
|---|---|---|
| CRITICAL-F01 | Typed outcome_unknown после Register failure в stream/fallback; loop no-replay regression PASS по JSON evidence. Реальные PG rollback/ambiguous/reset не воспроизводятся одной заменой ошибки в fake. | Аналогичный барьер; дополнительно присутствуют PG/wiring tests. Полная эквивалентность не доказана. |
| DELIVERY-F01 | Entry selection до prerequisites; fixture больше не форсирует opt-in. По source исправлено; no-stand PASS и selected negative записаны. | Также исправлено, entry regression suite. |
| BROKER-F01 | SQL сохраняет randomized seal при same-version replay; WHERE защищает version/digest. Есть PG replay/rotation evidence. Combined grant/OAuth proof отдельно открыт. | Аналогичный SQL invariant; больше runtime-wiring tests, без утверждения здесь об их свежем выполнении. |
| RUNTIME-F01 | Final encoded bound + escaped-ID follow-up выглядят исправленными для text/data. Это не исчерпывающая проверка всех publication/limit interleavings. | Bound + дополнительные pre-publication guards/tests. |
| RUNTIME-F02 | Bridge исправлен частично; Q3 polling/wait не закрыт. | Более полная polling progress реализация и negative/correlation tests. |
| RUNTIME-F03 | Маленькие URL-файлы работают; Q2 encoded-envelope defect остаётся. | Учитывает envelope budget и local file_error. |
| RUNTIME-F04 | Положительный document bridge есть; Q1 after-tool deny остаётся. | Accepted-output selection + отказ непринятого finalizer; более широкие negative tests. |
| DELIVERY-F02 | Manifest/lock переведены на1.2.6; packaging checks записаны. По source исправлено. | Chart/lock ещё не изменены относительно fix-base. |
| DELIVERY-F03 | Fault/send+cancel/no-replay и approval-refusal corpus добавлен. Live execution не было; immediate counter check после reject не доказывает отсутствие позднего asynchronous dispatch. | В данном diff требуемый новый corpus ещё не добавлен. |

## Выполненные общие регрессии — второй этап

На обоих pinned SHA запущены ОДИНАКОВЫЕ три probe-файла; исходники экспортированы
через git archive в отдельные /tmp directories, без worktree/ref mutations. Новые
тесты добавлены только в экспорты. Скрипт и SHA256 probes: [runner](run-quality-probes.py),
[results.json](results/2026-10-24/results.json). Полные Go JSON logs:
[Lite](results/2026-10-24/lite.jsonl), [основной](results/2026-10-24/original.jsonl).
Команда/ограничения: [README](README.md).

| Проверка | Lite8e879041 | Основнойa9b5de71 |
|---|---|---|
| Explicit document selection, after_tool allow | PASS | PASS |
| after_tool deny не оставляет final attachment IDs | **FAIL: ID остался** | PASS |
| Промежуточный документ без selection | PASS | PASS |
| Direct private HTTP, 16B /750KiB /1MiB | PASS все3 | PASS все3 |
| Stream fallback, 16B /750KiB | PASS оба | PASS оба |
| Stream fallback,1MiB: сохранить text +local file_error | **FAIL: outcome_unknown вместо Message** | PASS |
| Настоящий partner SSE,16B /750KiB | PASS оба | PASS оба |
| Partner SSE,1MiB: сохранить text +local file_error | **FAIL: error/outcome_unknown вместо Message** | PASS |
| Polling working snapshot ДО release следующего physical GET | **FAIL: snapshot удержан** | PASS |

Итого13 leaf cases на каждом SHA (15 Go test records с родительскими группами):
Lite9 PASS/4 FAIL, основной13 PASS/0 FAIL; SKIP0. Все три проверяемые группы
различают реализации. Второй полный запуск подтвердил результаты первого.
Финальный запуск: Lite13.04с, основной13.54с; это НЕ speed benchmark, кеши общие.
Go1.27.1, goolm, CGO0, -mod=readonly, GOPROXY=off, GOWORK=off, новый пустой HOME;
никаких унаследованных stand/DSN/model credentials. Новые HTTP fixtures loopback,
TLS fixtures — собственные ephemeral ports на private interface хоста (не loopback),
как требует существующий product testinfra; выполнялось разрешение hostname.
Это не ОС sandbox. Docker, настоящая PG, LLM и production acceptance не проверялись.

Важные границы:
- Q1 проверяет общий finalizer/Loop/acceptance и возвращаемые FinalAttachmentIDs
  с mock DocumentStore. Это НЕ полный A2A ingestion→browser/download тест и не
  доказательство уже случившейся пользовательской доставки запрещённого файла.
- Q2 действительно проходит private HTTP writer/client, TLS partner и download;
  все файлы, включая overflow, передают настоящий body. В исходном основном
  `a2a_message_files_test.go` overflow cases не пишут body: такой fixture может
  подтвердить обработку premature EOF вместо нужной base64 boundary. Новая общая
  проба эту слабость не наследует, и основной код всё равно проходит её.
- Q3 использует barrier второго GET, а не произвольный sleep/latency threshold.
  Подтверждён broker progress defect; полный UI/owner/reconnect corpus не выполнен.
- 9/13 не является «69% качества Lite»: cases целенаправленно проверяют три
  найденные проблемы, не случайную/полную выборку продукта.

## Почему прежние review этого не исключили

Review PASS и охват 49/49 изменённых файлов не гарантируют проверку исходных
пользовательских инвариантов в неизменённых consumers. В Q1 важен старый finalizer,
в Q2 — старый private writer, в Q3 — не изменённый polling adapter. Положительные
mock tests не заменяют отрицательные проверки на этих seam. Открытый execution
gap нельзя считать доказательством source correctness.

Мой предыдущий ответ тоже слишком доверял результату review. Корректная формулировка:
«Lite завершил заявленный local/source-review endpoint, но независимая проверка
критериев выявила незакрытые сценарии». Экономия parent calls не доказывает качество;
Session Info также не следует объявлять all-agent стоимостью без учёта child sessions.

## Сценарии и оставшаяся проверка, не расширение harness

Базовые контрпримеры1/2/3 выполнены выше. Полный желаемый scope шире этих probes:
1. A2A receive → explicit selection → after_tool deny → ZERO final attachments;
   отдельно success/intermediate/reset. Адаптировать driver к разрешённым branch
   tool interfaces, не переносить artifact_ids-only тест дословно в document bridge.
2. Context-less URL file у private broker HTTP boundary: tiny / около frame ceiling /
   больше ceiling / несколько parts; проверять exact bytes либо local file_error
   и сохранение text. Реальный JSON/SSE writer обязателен, не только Broker method.
3. Non-streaming partner с gated polling: working snapshot/progress появляется
   ДО release/timeout, не становится answer text и не смешивает call/owner.
4. Выполнить добавленный fault/approval corpus на отдельно разрешённом owned stand.

Не копировать все изменения между ветками автоматически. Сохранить обе реализации;
выбирать/объединять конкретные решения после regression evidence. Новые циклы,
лимитеры, автоматические фиксаторы и дополнительные instruction packs не нужны.
