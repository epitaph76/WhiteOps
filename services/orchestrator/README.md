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
