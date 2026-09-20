---
name: update-cs-service-on-d3
description: Deploy a cloudSolution service to the d3 environment. Use this skill whenever the user wants to deploy, release, or update a service on d3, mentions a PIPELINE_URL and TASK_ID, or says something like "выкатить на d3", "deploy to d3", "обнови сервис на d3". The skill waits for a GitLab CI pipeline to finish, extracts the Docker image tag and Helm chart version, copies the image to the registry, and creates a merge request in portal-deploy to update versions.yaml.
---

# Deploy cloudSolution service to d3

**Required inputs from the user:** `PIPELINE_URL`, `TASK_ID`

If either is missing — ask the user before doing anything.

**Important:** This process affects a shared environment. Execute each step carefully. If anything is ambiguous or unexpected, stop and ask the user.

---

## Step 1 — Parse PIPELINE_URL

From the URL (e.g. `https://gitlab-dev.t1.cloud/cloud-solution/cloud-audit/cloud-audit-config-sync/-/pipelines/498158`) extract:

- `PROJECT_PATH` — path between host and `/-/` (e.g. `cloud-solution/cloud-audit/cloud-audit-config-sync`)
- `SERVICE_NAME` — last segment of PROJECT_PATH (e.g. `cloud-audit-config-sync`)
- `PIPELINE_ID` — number after `/pipelines/` (e.g. `498158`)
- `PROJECT_PATH_ENCODED` — PROJECT_PATH with `/` replaced by `%2F`

---

## Step 2 — Wait for the pipeline to finish

```bash
glab api "projects/${PROJECT_PATH_ENCODED}/pipelines/${PIPELINE_ID}" | jq -r '.status'
```

Poll every 15 seconds until status is `success`. If status is `failed` or `canceled` — stop immediately and inform the user.

---

## Step 3 — Get DOCKER_TAG from kaniko-build logs

```bash
# Get kaniko-build job ID
KANIKO_JOB_ID=$(glab api "projects/${PROJECT_PATH_ENCODED}/pipelines/${PIPELINE_ID}/jobs" \
  | jq '.[] | select(.name=="kaniko-build") | .id')

# Get the image push line (exclude cache layers, take last match)
glab api "projects/${PROJECT_PATH_ENCODED}/jobs/${KANIKO_JOB_ID}/trace" \
  | grep "Pushing image" | grep -v "\-cache:" | tail -1
```

The line looks like:
```
INFO[0034] Pushing image to gitlab-registry-dev.t1.cloud/cloud/registry-snapshot/portal/cloud-audit-config-sync:b773875d-13
```

Extract from it:
- `DOCKER_TAG` — the part after the last `:` (e.g. `b773875d-13`)
- `DOCKER_IMAGE` — `SERVICE_NAME:DOCKER_TAG` (e.g. `cloud-audit-config-sync:b773875d-13`)

If the line is not found or the output is unexpected — stop and show it to the user.

---

## Step 4 — Get CHART_VERSION from Chart.yaml

```bash
glab api "projects/${PROJECT_PATH_ENCODED}/repository/files/charts%2F${SERVICE_NAME}%2FChart.yaml/raw?ref=master" \
  | grep "^version:" | awk '{print $2}'
```

This gives `CHART_VERSION` (e.g. `0.1.2`).

---

## Step 5 — Copy image to registry

```bash
cd /home/dyens/dev/croc/cloud-solution
./copy_images_to_registry.sh ${SERVICE_NAME}:${DOCKER_TAG}
```

Wait for the script to finish successfully before continuing.

---

## Step 6 — Create MR in portal-deploy

### Convert SERVICE_NAME to camelCase

`cloud-audit-config-sync` → `cloudAuditConfigSync`  
Rule: split by `-`, capitalize each word except the first, join.

This is the key used in `versions.yaml` under `versions.cloudSolution.{camelCaseServiceName}`.

### Update versions.yaml and push

```bash
cd /home/dyens/dev/croc/portal-deploy
git checkout main
git pull

# If branch already exists — delete it and recreate
git branch -D "${TASK_ID}-${SERVICE_NAME}" 2>/dev/null || true
git checkout -b "${TASK_ID}-${SERVICE_NAME}"
```

Open `environments/t1-d3/versions.yaml` with the Read tool, find the block under `versions.cloudSolution.{camelCaseServiceName}`, then use the Edit tool to update **both** fields:

```yaml
# Before:
    cloudAuditConfigSync:
      app: c268cf9d-10
      chart: 0.1.1

# After:
    cloudAuditConfigSync:
      app: b773875d-13    # ← DOCKER_TAG
      chart: 0.1.2        # ← CHART_VERSION
```

Do not use sed/awk — use the Read + Edit tools to avoid corrupting the YAML.
After editing, verify the changed lines look correct before committing.

```bash
cd /home/dyens/dev/croc/portal-deploy
git add environments/t1-d3/versions.yaml
git commit -m "Update ${SERVICE_NAME} on d3"
git push -u origin "${TASK_ID}-${SERVICE_NAME}"
```

### Create the MR

```bash
cd /home/dyens/dev/croc/portal-deploy
glab mr create \
  --target-branch main \
  --title "${TASK_ID} Update ${SERVICE_NAME} on d3" \
  --description "" \
  --yes
```

---

## Step 7 — Print the summary

After MR is created, print:

```
MR:            <MR link>
DOCKER_IMAGE:  cloud-audit-config-sync:b773875d-13
CHART_VERSION: 0.1.2
```
