# WhiteOps Orchestrator (MVP)

Standalone orchestration service for `Codex manager + 2 Qwen workers`.
`cli-bridge` is only a provider/debug layer.

## Execution Modes

- `EXECUTION_MODE=bridge`
  Orchestrator sends agent calls to `cli-bridge` (`POST /runs`).
- `EXECUTION_MODE=api`
  Orchestrator sends agent calls to an external provider (`API_RUN_URL`) with the same run contract.

## Bridge Autostart

In `bridge` mode the orchestrator can start `cli-bridge` automatically if it is offline:

- `BRIDGE_AUTOSTART=true`
- `BRIDGE_SHOW_CONSOLE=true` (show bridge stdout/stderr in the current console)
- `BRIDGE_START_CMD=node`
- `BRIDGE_START_ARGS=node_modules/tsx/dist/cli.mjs watch src/index.ts`
- `BRIDGE_START_CWD=C:/project/WhiteOps/services/cli-bridge`

## Quick Start (PowerShell)

```powershell
cd C:\project\WhiteOps\services\orchestrator
Copy-Item .env.example .env
npm install
npm run dev
```

Health check:

```powershell
Invoke-RestMethod http://127.0.0.1:7081/health
```

Optional PostgreSQL snapshot backend (Docker):

```powershell
cd C:\project\WhiteOps
docker compose up -d postgres
```

Use `.env` values:

- `GRAPH_STORE_PG_URL=postgresql://whiteops:whiteops@127.0.0.1:5432/whiteops`
- `GRAPH_STORE_PG_TABLE=orchestrator_graph_store_snapshot`

## Frontend-Oriented API

### Why this API exists

Flutter should not wait on a single long HTTP request.
Use async tasks + polling and/or SSE stream.

### Endpoints

- `POST /tasks/minimal`
  Create async orchestration task and start it in background.
- `GET /tasks`
  List tasks (optional query: `limit`).
- `GET /tasks/:taskId`
  Get full task snapshot (status, timeline, result, errors).
- `POST /tasks/:taskId/cancel`
  Request cancellation.
- `GET /tasks/:taskId/events`
  SSE stream for realtime updates.

Cancellation is best-effort: if worker one-shot calls are already running, they may finish.

Task statuses:

- `queued`
- `planning`
- `running`
- `cancel_requested`
- `completed`
- `failed`
- `canceled`

### Create Task

Request:

```json
{
  "task": "string",
  "cwd": "C:/project/WhiteOps",
  "managerTimeoutMs": 60000,
  "workerTimeoutMs": 120000
}
```

Response (`202 Accepted`):

```json
{
  "id": "uuid",
  "kind": "minimal",
  "status": "queued",
  "input": {
    "task": "string",
    "cwd": "C:/project/WhiteOps",
    "managerTimeoutMs": 60000,
    "workerTimeoutMs": 120000
  },
  "cancelRequested": false,
  "createdAt": "ISO",
  "updatedAt": "ISO",
  "timeline": []
}
```

If `task` is omitted, the default built-in demo task is used.

### SSE Stream (`GET /tasks/:taskId/events`)

Events:

- `snapshot` (full task snapshot on connect)
- `task_event` (incremental updates)

`task_event` example:

```json
{
  "taskId": "uuid",
  "status": "running",
  "cancelRequested": false,
  "event": {
    "sequence": 7,
    "at": "ISO",
    "type": "progress_worker_started",
    "data": {
      "workerId": "qwen-1"
    }
  }
}
```

### Flutter Integration Notes

- Start task with `POST /tasks/minimal`.
- Subscribe to `/tasks/:taskId/events` for realtime UI.
- Also poll `GET /tasks/:taskId` as reconnect fallback.
- Store `taskId` in local state so UI can recover after app restart.

## Legacy Sync Endpoint

Still available for manual/debug usage:

- `POST /orchestrations/minimal`

This endpoint is synchronous and not recommended for frontend UX.

## API Provider Contract (`EXECUTION_MODE=api`)

`API_RUN_URL` must accept:

```json
{
  "agentId": "codex | qwen",
  "prompt": "string",
  "cwd": "optional string",
  "timeoutMs": 12345
}
```

And return:

```json
{
  "output": "string",
  "timedOut": false,
  "durationMs": 1234
}
```

## Graph Orchestration API (Backend for Visual Editor)

### Graph entities in storage

- `orchestration_graph`
- `graph_node`
- `graph_edge`

### Graph CRUD and validation

- `GET /graphs`
- `POST /graphs`
- `GET /graphs/:id`
- `PUT /graphs/:id`
- `POST /graphs/:id/validate`

### Graph runs

- `POST /graphs/:id/runs` (creates run bound to a specific graph revision; supports optional `cwd`)
- `GET /graphs/:id/runs`
- `GET /graphs/:id/runs/:runId`
- `GET /graph-runs/:runId`
- `POST /graph-runs/:runId/cancel`
- `GET /graph-runs/:runId/events` (SSE realtime stream)
- `GET /graph-runs/:runId/events/history` (replay events since `afterSequence`)

Realtime event types:

- `graph_run_started`
- `graph_run_resumed`
- `node_status_changed`
- `node_log_chunk`
- `node_result_ready`
- `graph_run_finished`

### Node dialog API

- `POST /nodes/:nodeId/chat`
- `GET /nodes/:nodeId/messages`
- `GET /nodes/:nodeId/logs` (supports `afterSequence` for incremental reads)

The run payload includes manager trace entries (task assignment, reason, confirmation status)
and node artifacts (`diffPatch`, `stdout`, `stderr`, `resultFiles`).

`POST /nodes/:nodeId/chat` body fields:

- `message` (required)
- `graphId` (optional, required only if node id is ambiguous)
- `runId` (optional, to bind chat/logs to a graph run)
- `timeoutMs` (optional)
- `cwd` (optional)

## Authentication and Access Control

Authentication is token-based and can be enabled for graph/run/node endpoints:

- `AUTH_ENABLED=true|false`
- `AUTH_HEADER=Authorization`
- `AUTH_TOKENS=token1:userId1[:role],token2:userId2[:role]`
- `AUTH_DEFAULT_USER_ID=local-dev`

Role values: `user`, `admin`.
Access control is applied per graph owner + ACL (`editors`, `viewers`), and inherited by graph runs.
By design, auth/ACL checks are applied to graph/run/node APIs.
Legacy `/tasks/*` endpoints remain open for local dev UX.

## Storage Model

Graph storage is persisted as snapshot JSON containing:
graphs, runs, run events, node messages, node logs, and node-attempt idempotency records.

Backends:

- File snapshot (`GRAPH_STORE_PATH`) always available.
- PostgreSQL snapshot mirror (`GRAPH_STORE_PG_URL`) optional; when enabled, snapshot is loaded/saved via Postgres as durable storage.

Queued/running graph runs are recovered and resumed on orchestrator restart.
