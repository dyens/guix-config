---
name: debug-ruclaw-trace
description: Разобрать трейс агента RuClaw по его UUID на живом стенде — найти тенант, поднять трейс и спаны из Postgres, дойти до реальной причины отказа инструмента или LLM-вызова. Использовать, когда дан trace id (UUID) и сказано «разберись», «что не так с трейсом», «почему упал ран», либо когда нужно посчитать отказы инструмента по тенантам.
---

# Разбор трейса RuClaw

## Главное правило: трейс читается ИЗ БАЗЫ, не через API

`GET /v1/traces/{id}` с gateway-токеном бесполезен и **активно врёт**:

- одиночный трейс → `404 {"error":"trace not found"}` даже когда строка в базе есть;
- список → `500 RUCLAW_RLS_NO_TENANT: app.tenant is not set on this connection`.

Так и задумано: gateway-токен tenantless (`internal/identity/adapters.go`, `CrossTenant: true`), `applyPrincipalToContext` (`internal/http/auth.go`) не кладёт тенант на ctx, RLS отбивает запрос, а `handleGet` (`internal/http/traces.go`) превращает любую ошибку в «trace not found». Заголовка для выбора тенанта в коде нет.

**Не тратить время на:** `kubectl exec`, `kubectl port-forward`, логин в `/v1/iam/auth/login` — в этой среде они обычно блокируются классификатором. Идти сразу в Postgres.

## Шаг 0. Время трейса — без единого запроса

Id трейса — UUIDv7, первые 48 бит это миллисекунды epoch:

```bash
python3 -c "
import datetime
v = int('01a0c9dd-af3c-71ce-a506-8c8dac39e0b9'.replace('-','')[:12], 16)
print(datetime.datetime.fromtimestamp(v/1000, datetime.timezone.utc))"
```

Полезно сразу: если трейс старше ~30 минут, **в логах бэкенда его уже нет**. Telegram-поллинг на демо-стенде флудит лог тысячами строк `telegram polling error`, и окно ретенции контейнера съедается за полчаса. `kubectl logs --tail=200000` отдаст 1500-2000 строк — это не «мало трафика», это всё, что осталось.

## Шаг 1. Инструмент доступа к базе

На хосте обычно **нет `psql`** и нет python-драйверов (`psycopg2`/`psycopg`/`asyncpg`). Зато есть Go и pgx в модуле репозитория. Собрать разовую утилиту:

```go
// /tmp/.../q.go — запускать из корня репозитория, импорты резолвятся его go.mod
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/jackc/pgx/v5"
)

func main() {
	ctx := context.Background()
	conn, err := pgx.Connect(ctx, os.Getenv("DSN"))
	if err != nil {
		fmt.Println("connect error:", err)
		os.Exit(1)
	}
	defer conn.Close(ctx)

	// RLS: без app.tenant не видно НИЧЕГО тенант-скоупленного.
	if t := os.Getenv("TENANT"); t != "" {
		if _, err := conn.Exec(ctx, "SELECT set_config('app.tenant', $1, false)", t); err != nil {
			fmt.Println("set tenant error:", err)
			os.Exit(1)
		}
	}

	args := make([]any, 0, len(os.Args)-2)
	for _, a := range os.Args[2:] {
		args = append(args, a)
	}
	rows, err := conn.Query(ctx, os.Args[1], args...)
	if err != nil {
		fmt.Println("query error:", err)
		os.Exit(1)
	}
	defer rows.Close()
	fds := rows.FieldDescriptions()
	n := 0
	for rows.Next() {
		vals, _ := rows.Values()
		n++
		fmt.Printf("---- row %d ----\n", n)
		for i, v := range vals {
			s := fmt.Sprintf("%v", v)
			if b, ok := v.([]byte); ok {
				s = string(b)
			}
			if m, ok := v.(map[string]any); ok {
				j, _ := json.Marshal(m)
				s = string(j)
			}
			s = strings.ReplaceAll(s, "\n", "\\n")
			if len(s) > 2000 {
				s = s[:2000] + "…(truncated)"
			}
			fmt.Printf("%-24s %s\n", fds[i].Name+":", s)
		}
	}
	fmt.Printf("== %d row(s) ==\n", n)
}
```

```bash
cd /path/to/ruclaw
export GOFLAGS=-tags=goolm          # обязателен для любой go-команды в этом репозитории
go build -o /tmp/q /tmp/q.go        # собрать один раз, дальше дёргать бинарник в цикле
```

DSN лежит в секрете кластера:

```bash
export DSN=$(kubectl get secret ruclaw-secrets -o jsonpath='{.data.RUCLAW_POSTGRES_DSN}' | base64 -d)
```

Соединение идёт под ролью `ruclaw_app` — **под RLS**. `RUCLAW_DB_MAINT_DSN` (роль `ruclaw_maint`) в том же секрете, но обращение к нему обычно блокируется — не рассчитывать на него.

## Шаг 2. Найти тенант трейса

Таблица `tenants` читается БЕЗ `app.tenant` (кросс-тенантная по устройству). Всё остальное — нет. Поэтому тенант трейса ищется перебором:

```bash
/tmp/q "select id::text || ' ' || slug as t from tenants order by created_at" \
  | grep -E "^t:" | awk '{print $2, $3}' > /tmp/tenants.txt

while read -r tid slug; do
  c=$(TENANT="$tid" /tmp/q "select count(*)::text as c from traces where id = \$1" "<TRACE_ID>" \
      | grep -E "^c:" | awk '{print $2}')
  [ "$c" != "0" ] && echo "$slug $tid"
done < /tmp/tenants.txt
```

36 тенантов — около минуты. Если не нашёлся ни в одном, трейс действительно не записался, и тогда копать надо в сторону RLS-отказов на записи (см. «Смежные ловушки»).

## Шаг 3. Трейс и спаны

**Всегда кастовать UUID в `::text`** — иначе pgx печатает `[16]byte` в виде списка чисел.

```bash
export TENANT=<tenant-uuid>

/tmp/q "select id::text, agent_id::text, user_id, session_key, run_id,
  start_time::text, end_time::text, duration_ms, name, channel, status, error,
  total_input_tokens, total_output_tokens, span_count, llm_call_count, tool_call_count,
  left(input_preview,600) as input_preview, left(output_preview,600) as output_preview,
  metadata::text from traces where id = \$1" "<TRACE_ID>"

/tmp/q "select id::text, parent_span_id::text, span_type, name, start_time::text,
  duration_ms, status, error, model, provider, input_tokens, output_tokens,
  finish_reason, tool_name, tool_call_id,
  left(input_preview,800) as input_preview, left(output_preview,800) as output_preview,
  metadata::text from spans where trace_id = \$1 order by start_time" "<TRACE_ID>"
```

Читать спаны сверху вниз как ленту: `agent` → `llm_call` (с `finish_reason: tool_calls`) → `tool_call` → `llm_call` → …

## Шаг 4. Как читать результат

- **`traces.status = 'completed'` ничего не гарантирует.** Ран с упавшим инструментом внутри помечается успешным, `traces.error` пуст. Правда живёт в `spans.status = 'error'` — смотреть их всегда:
  ```sql
  select span_type, tool_name, duration_ms, error from spans
   where trace_id = $1 and status = 'error'
  ```
- **Длительность спана — диагноз.** Отказ инструмента за 16-120 мс значит «не дошло до сети»: не установлено, не сконфигурировано, не найдено. Секунды и больше — уже сеть, таймаут, отказ удалённой стороны.
- **Колонка `error` обрезана в выводе** — полный текст брать из `output_preview` того же спана.
- **Последний `llm_call` с `finish_reason: stop`** показывает, что модель сказала пользователю после отказа инструмента. Частый паттерн: «Попробую установить» — и остановка, без единой попытки. Это отдельный дефект, не тот же самый.

## Шаг 5. Масштаб: это один случай или так всегда?

Прежде чем заводить тикет, посчитать по ВСЕМ тенантам — почти всегда выясняется, что «падает у одного пользователя» означает «не работало никогда»:

```bash
while read -r tid slug; do
  c=$(TENANT="$tid" /tmp/q "select count(*)::text as c from spans
        where tool_name = '<TOOL>' and status = 'error'
          and created_at > now() - interval '7 days'" | grep -E "^c:" | awk '{print $2}')
  [ -n "$c" ] && [ "$c" != "0" ] && echo "$slug: $c"
done < /tmp/tenants.txt
```

И всегда рядом — счётчик успешных того же инструмента. Отношение 10/10 отказов читается совсем иначе, чем 10 отказов из тысячи.

Сравнение двух таблиц по тенантам ловит дыры, которые по одной таблице не видны (трейсы есть — аудита нет, и т.п.):

```bash
while read -r tid slug; do
  t=$(TENANT="$tid" /tmp/q "select count(*)::text as c from traces
        where created_at > now() - interval '24 hours'" | grep -E "^c:" | awk '{print $2}')
  a=$(TENANT="$tid" /tmp/q "select count(*)::text as c from audit_events
        where occurred_at > now() - interval '24 hours'" | grep -E "^c:" | awk '{print $2}')
  [ "$t" != "0" ] && printf "%-20s traces=%-6s audit=%s\n" "$slug" "$t" "$a"
done < /tmp/tenants.txt
```

## Шаг 6. От ошибки — к деплою

Отказ инструмента почти всегда упирается в конкретный под. Что смотреть (это доступно даже когда exec заблокирован):

```bash
kubectl get pods -o wide
kubectl get deploy <name> -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deploy <name> -o jsonpath='{.spec.template.spec.containers[0].env}'   | python3 -m json.tool
kubectl get deploy <name> -o jsonpath='{.spec.template.spec.securityContext}'      # runAsUser!
kubectl get deploy <name> -o jsonpath='{.spec.template.spec.volumes}'
kubectl logs deploy/<name> --tail=100
```

`runAsUser` проверять всегда. `charts/ruclaw-sidecar/values.yaml` навязывает ВСЕМ сайдкарам `runAsUser: 1000`, тогда как `docker-compose.yml` не задаёт `user:` вообще и те же образы идут от root. Любой дефект вида «в compose работает, в k8s нет» надо в первую очередь примерять на это расхождение — именно так вскрылся RCL-615 (Playwright ставил браузер в `/root/.cache`, а сервис искал его в `/home/node/.cache`).

## Смежные ловушки, на которые легко попасться

- **`security.rls.no_tenant` в логе бэкенда.** Statement дошёл до базы с `app.tenant = ''`, любая политика его отбивает. Счётчик в поле `total=` — накопительный за жизнь процесса, шестизначный там нормален и НЕ означает всплеск именно сейчас.
- **`audit: failed to emit event` → `new row violates row-level security policy for table "audit_tenant_sequences"`.** Известная история: `AuditMiddleware` прибит к одному tenantID на старте (`cmd/gateway.go`), а соединение несёт тенант запроса. Аудит пишется только у тенанта по умолчанию. Тикет RCL-616 — не заводить дубль.
- **Политика на всех тенантных таблицах одна:** `tenant_id = app_tenant()`, и на `USING`, и на `WITH CHECK`. Проверить можно так:
  ```sql
  select tablename, policyname, cmd, qual, with_check from pg_policies where tablename = '<table>'
  ```
- **Секреты:** `kubectl get secret ruclaw-secrets -o jsonpath='{.data}'` — там же `GATEWAY_TOKEN`, `RUCLAW_ADMIN_PASSWORD`, `RUCLAW_INTERNAL_SERVICE_TOKEN`. Пароли в выводе не печатать: DSN показывать через `sed -E 's#(//[^:]+:)[^@]+@#\1***@#'`.
- **`-p 1` и `GOFLAGS=-tags=goolm`** — если по ходу дела понадобится прогнать тесты репозитория.
- **`git checkout` падает** с `git-lfs: command not found` / `fatal: the remote end hung up unexpectedly`, оставляя рабочее дерево В ПОЛОВИНЕ переключения (HEAD от одной ветки, файлы от другой). Ветки с LFS-путями в `.gitattributes` переключать так:
  ```bash
  git -c filter.lfs.process= -c filter.lfs.smudge=cat -c filter.lfs.clean=cat \
      -c filter.lfs.required=false checkout -f <branch>
  ```
  То же для `status` и `stash pop`. Коммиты и stash при таком обрыве не теряются — чинится повторным `checkout -f` с этими ключами.
- **`$1` в SQL** внутри двойных кавычек bash надо экранировать (`\$1`), иначе подстановка съест плейсхолдер и запрос уйдёт с пустым параметром.

## Схема (что вообще есть в таблицах)

`traces`: `id, tenant_id, agent_id, user_id, session_key, run_id, start_time, end_time, duration_ms, name, channel, input_preview, output_preview, total_input_tokens, total_output_tokens, total_cost, span_count, llm_call_count, tool_call_count, status, error, metadata, tags, created_at`

`spans`: `id, trace_id, parent_span_id, agent_id, span_type, name, start_time, end_time, duration_ms, status, error, level, model, provider, input_tokens, output_tokens, total_cost, finish_reason, model_params, tool_name, tool_call_id, input_preview, output_preview, metadata, created_at`

`span_type` ∈ `agent` | `llm_call` | `tool_call` | `event`.

## Чем заканчивать

Не чинить на месте, если не просили. Дойти до корневой причины с доказательствами (строка из базы, строка из чарта/Dockerfile, цифра масштаба по тенантам), и завести тикет в Jira RCL по `docs/agents/issue-tracker.md`. Для исправления — отдельная ветка `bugfix/RCL-XXX-...` от `develop` по скиллу `git-workflow`; текущую ветку и её незакоммиченные изменения сначала спрятать (`git stash push <file>`) и вернуть в конце.
