# WhiteOps

WhiteOps - backend-first оркестратор AI-агентов для задач разработки.
В репозитории сейчас рабочий MVP: `cli-bridge` + `orchestrator` + (опционально) desktop клиент.

## Что уже реализовано

### 1) CLI bridge (`services/cli-bridge`)

Локальная прослойка для запуска `codex` и `qwen` через CLI.

- one-shot вызовы: `POST /runs`
- интерактивные PTY-сессии: `POST /sessions`, `POST /sessions/:id/prompt`, `DELETE /sessions/:id`
- диагностика: `GET /health`, `GET /agents`, `GET /sessions`

Документация: `services/cli-bridge/README.md`.

### 2) Orchestrator (`services/orchestrator`)

Поддерживает два режима выполнения:

- `EXECUTION_MODE=bridge` - вызовы в `cli-bridge`
- `EXECUTION_MODE=api` - вызовы во внешний `API_RUN_URL`

Есть два блока API:

- legacy/minimal async задачи: `POST /tasks/minimal` + `GET /tasks/:id/events`
- графовая оркестрация (backend для визуального редактора):
  - `POST /graphs`, `GET /graphs/:id`, `PUT /graphs/:id`, `POST /graphs/:id/validate`
  - `POST /graphs/:id/runs`, `GET /graphs/:id/runs`, `GET /graphs/:id/runs/:runId`
  - `POST /graph-runs/:runId/cancel`, `GET /graph-runs/:runId/events`
  - `POST /nodes/:nodeId/chat`, `GET /nodes/:nodeId/messages`, `GET /nodes/:nodeId/logs`

Реализованы:

- topological scheduler по DAG
- параллельные ветки
- retry/timeout/cancel на уровне node
- realtime события (`graph_run_started`, `node_status_changed`, `node_log_chunk`, `node_result_ready`, `graph_run_finished`)
- manager trace (назначение, причина, confirmation)
- node artifacts (`diffPatch`, `stdout`, `stderr`, `resultFiles`)
- token auth + ACL (owner/editor/viewer) для graph/run/node API

Документация: `services/orchestrator/README.md`.

### 3) Flutter desktop клиент (`apps/orchestrator_desktop`)

Тонкий UI-клиент для minimal-task API orchestrator (`/tasks/*`).

## Ограничения текущего MVP

- Persistency сделана snapshot-моделью (file + optional PostgreSQL JSONB), без нормализованной SQL-схемы графов.
- Нет Redis/очередей внешнего брокера.
- Нет production IAM/SSO; только простой token-based auth для graph/run/node API.

## Быстрый запуск (локально)

### CLI bridge

```powershell
cd C:\project\WhiteOps\services\cli-bridge
Copy-Item .env.example .env
npm install
npm run dev
```

### Orchestrator

```powershell
cd C:\project\WhiteOps
docker compose up -d graph_store_postgres

cd C:\project\WhiteOps\services\orchestrator
Copy-Item .env.example .env
npm install
npm run dev
```

Проверки:

```powershell
Invoke-RestMethod http://127.0.0.1:7071/health
Invoke-RestMethod http://127.0.0.1:7081/health
```

`start-whiteops.bat` теперь поднимает отдельный `graph_store_postgres` из `docker-compose.yml` автоматически (если Docker доступен).

## Дорожная карта

- Перевод graph storage на persistent DB.
- Расширение auth/audit.
- UI граф-редактора во Flutter.

Текущий рабочий roadmap: `docs/orchestrator-demo/graph-editor-roadmap-ru.md`.
