# WhiteOps CLI Bridge (MVP)

Отдельный debug-сервис для управления локальными CLI-агентами (`codex`, `qwen`) из backend-оркестратора.

## Что уже умеет

- регистрирует доступные CLI-агенты через env;
- создаёт и держит PTY-сессии под выбранного агента;
- отправляет prompt в конкретную сессию;
- поддерживает одноразовый режим (`run once`) без ручного управления сессией;
- возвращает output, `timedOut` и `durationMs`.

## Запуск

```bash
cd services/cli-bridge
cp .env.example .env
npm install
npm run dev
```

## Конфиг агентов

- `AGENT_CODEX_CMD`, `AGENT_CODEX_ARGS`
- `AGENT_QWEN_CMD`, `AGENT_QWEN_ARGS`

Пример:

```env
AGENT_CODEX_CMD=codex
AGENT_CODEX_ARGS=
AGENT_QWEN_CMD=qwen
AGENT_QWEN_ARGS=code
```

## API

- `GET /health`
- `GET /agents`
- `GET /sessions`
- `POST /sessions` body: `{ "agentId": "codex" | "qwen", "cwd"?: "C:/project" }`
- `POST /sessions/:sessionId/prompt` body: `{ "prompt": "...", "timeoutMs"?: 45000, "idleMs"?: 1200 }`
- `DELETE /sessions/:sessionId`
- `POST /runs` body: `{ "agentId": "codex" | "qwen", "prompt": "...", "cwd"?: "C:/project" }`
