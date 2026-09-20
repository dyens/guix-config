---
name: jira
description: Fetch and display Jira ticket details (summary, description, status, assignee, comments). Use this skill whenever the user provides a Jira ticket URL or ticket ID (e.g. PCS-1234, PROJ-567), asks to look up a Jira issue, or references a Jira task in conversation. Trigger proactively when a Jira URL like https://jira.*.*/browse/* appears in the message.
---

# Jira Skill

Fetch Jira ticket information using the REST API v2 and the `JIRA_API_TOKEN` environment variable.

## How to fetch a ticket

1. Extract the ticket ID from the user's message. Accepted formats:
   - Full URL: `https://jira.t1-cloud.ru/browse/PCS-4549` → ticket ID: `PCS-4549`, base URL: `jira.t1-cloud.ru`
   - Short ID: `PCS-4549` → use default base URL `jira.t1-cloud.ru`

2. Run this command via Bash:

```bash
TOKEN=$(printenv JIRA_API_TOKEN) && curl -s \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://<BASE_URL>/rest/api/2/issue/<TICKET_ID>"
```

3. Parse the JSON response with python3:

```bash
TOKEN=$(printenv JIRA_API_TOKEN) && curl -s \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://<BASE_URL>/rest/api/2/issue/<TICKET_ID>" | python3 -c "
import sys, json
d = json.load(sys.stdin)
f = d['fields']
print('Summary:', f['summary'])
print('Status:', f['status']['name'])
print('Assignee:', (f.get('assignee') or {}).get('displayName', 'Unassigned'))
print('Reporter:', (f.get('reporter') or {}).get('displayName', ''))
print()
print('Description:')
print(f.get('description') or '(no description)')
"
```

## Auth details

- Token: read via `TOKEN=$(printenv JIRA_API_TOKEN)` — always use this form so the shell expands the variable correctly before passing to curl.
- Auth type: check `JIRA_AUTH_TYPE` env var (defaults to `bearer`). Currently only bearer is used.

## Output format

Present the ticket info clearly in markdown:

```
**[TICKET-ID] Summary text**
Status: In Progress | Assignee: John Doe

Description:
<description text>
```

If the response is a 401 error, tell the user that `JIRA_API_TOKEN` is not set or is invalid.
If the response is a 404, tell the user the ticket was not found.
