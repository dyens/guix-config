# Lite v2: результат повторного эксперимента

## Факты

- Session `01a17045-e0b8-7006-bc8c-6e239f4aa97e`, первый user
  2026-10-24T23:37:02.381Z, final2026-10-25T00:19:54.469Z: **42мин52с**.
- Actual model: openai-codex/gpt-6.1-sol/medium, как Lite v1.
- Parent Session Info:272 calls,30,382,826 total tokens,$4.334. Это не all-agent cost.
- Context к концу277452 tokens; resets0. Три workflow round (6 child passes)
  против двух rounds первого Lite. Родитель не читал готовые чужие fixes по отчёту;
  все20 frozen input hashes независимо проверены, неизменны.
- Candidate `d5189d42b8f39adc4e7d0f33520cb25695e6c2bd`, исходный base2cbf2458;
  рабочее дерево проверено clean, push/merge не выполнялись.

Первый Lite:31мин23с,$3.866/278 parent calls. V2 дольше примерно37%, parent bill
выше примерно12%; один повтор знакомой задачи, общие кеши, scope/rounds различаются,
поэтому это не статистическая оценка профилей.

## Что действительно улучшилось

- Итог различает proven/partial/unverified, не объявляет production acceptance.
- Evaluator выполнил собственные differential probes; достигнутый escaped-ID
  overflow подтверждён до/после. Недостижимый Wire256 пример не принят на веру.
- Source review дополнительно нашёл и помог исправить MIME projection defect.

Это полезно, но не доказывает устранение остальных исходных ошибок.

## Внешний holdout: улучшения по трём измеряемым сценариям НЕТ

Неизменённые13 probes первого аудита независимо запущены на новом pinned candidate.
Git archive в `/tmp/pi-lite-v2-holdout-ib8vvzes/run`, probes только в экспорте;
никаких правок/ресурсов работающего checkout, Docker/PG/LLM calls. Собственные
ephemeral HTTP/private-interface TLS fixtures, Go cache shared, sanitized env,
Go1.27.1/goolm/CGO0/-mod=readonly/GOPROXY off. Время12.99с — не performance benchmark.

[Полные результаты и fingerprints](results/2026-10-25-lite-v2/results.json),
[Go JSON log](results/2026-10-25-lite-v2/lite-v2.jsonl).

| Сценарий | Lite v1 | Lite v2 | Основной a9b5de71 (предыдущий запуск) |
|---|---|---|---|
| after_tool deny не оставляет FinalAttachmentIDs | FAIL | **FAIL** | PASS |
| Context-less URL1MiB, stream fallback: text+file_error | FAIL | **FAIL: outcome_unknown** | PASS |
| Context-less URL1MiB, partner SSE: text+file_error | FAIL | **FAIL: error/outcome_unknown** | PASS |
| Polling working snapshot до release второго GET | FAIL | **FAIL** | PASS |

Положительные controls проходят; v2 **9 PASS/4 FAIL**, coverage_ok=true,SKIP0.
Это четыре failing leaf cases для трёх проблем, а не процент общего качества.
Q1 наблюдает Loop/finalizer и возвращаемые IDs с mock DocumentStore, не фактический
browser download. Q2 проходит настоящую private HTTP boundary. Q3 — настоящий
broker polling, не весь WebSocket/UI. Границы/источники tests — в evaluation README.

### Как воспроизведён новый candidate существующим runner

Использован тот же `run-quality-probes.py` и те же файлы probes, без изменения
исходных pinned defaults. В одноразовом Python invocation модуль импортирован через
importlib, `CANDIDATES={'lite-v2':'d5189d42b8f39adc4e7d0f33520cb25695e6c2bd'}`,
затем main с `--repo /home/dyens/dev/croc/ruclaw --out <new directory>`.
Фактические candidate/command/archive/probe hashes записаны в results.json;
runner_sha256 относится к неизменённому файлу, override указан здесь явно.

## Почему behavioral evaluator не исключил эти дефекты

- RUNTIME-F04 записан partial: выполнен projection-denied test, но он не проверяет
  отказ acceptance уже выполненного finalize_attachments. Нужный consumer seam
  оставлен в группе «live after-tool E2E gap», хотя bounded local probe доступен.
- RUNTIME-F03 positive URL ingestion вообще не выполнен evaluator: он счёл private-
  interface TLS fixture вне своей authority. В реальном user launch explicit
  HTTP/TLS fixtures разрешены (проверено наличие этой строки). Workflow передаёт
  finding request/evidence, но не точный per-run scope пользовательских grants;
  fresh child не наследует user conversation. Это вероятный дефект handoff, а не
  основание автоматически ослабить resource restrictions. Сам role prompt также
  разрешает inspected owned fixtures; почему разрешение сужено, надо отдельно
  разбирать. Missing live stand не объясняет невозможность данного local test.
- RUNTIME-F02 есть producer/mock progress и coordinator assertions, но реальный
  non-streaming polling consumer до окончания ожидания не проверен. Partial UI
  proof не равен отсутствию доступного local counterexample.

Таким образом v2 сделал статусы честнее и нашёл другие дефекты, но поведенческие
ошибки, определившие изменение процесса, повторились. Строка «все source-причины
обработаны» в итоговом producer report всё ещё не удостоверена внешними probes.

## Решение на этом срезе

Не объявлять v2 победителем/эквивалентным качеством и не начинать очередной запуск
с новой порцией общих инструкций. Не исправлять продукт вручную ради метрики.
Следующее обсуждение процесса должно разделить: точную передачу authority свежему
verifier и полноту заранее зафиксированных поведенческих scenarios/negative checks.
Повтор этого же известного кейса после наших holdouts не докажет generalization.
Никаких новых profile changes, commits или product fixes при этом измерении.
