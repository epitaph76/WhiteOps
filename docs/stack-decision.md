# Stack Decision (MVP)

Дата фиксации: `2026-03-09`

## Текущее решение (реализовано)

- Основной backend orchestrator: `Node.js + TypeScript + Fastify`
- Отдельная debug-прослойка CLI bridge: `Node.js + TypeScript + Fastify + node-pty`
- Транспорт между orchestrator и bridge: `HTTP` (`POST /runs`)
- Realtime для frontend: `SSE`
- Поддерживаемые агенты в MVP: `codex`, `qwen`
- Хранилище orchestrator: `in-memory`

## Почему так

- Быстрое прототипирование оркестрации без API-расходов в каждом цикле.
- Изоляция рисков: CLI-процессы и PTY вынесены в отдельный сервис (`cli-bridge`).
- Простой и прозрачный runtime для отладки scheduler/logs/events.

## Что отложено

- `PostgreSQL`/персистентность для графов и запусков.
- `Redis`/очереди фоновых задач.
- Production-auth (IAM/SSO/JWT rotation) вместо простого token-based доступа.

## Конфигурация агентов

Агенты bridge задаются через env:

- `AGENT_CODEX_CMD`, `AGENT_CODEX_ARGS`
- `AGENT_QWEN_CMD`, `AGENT_QWEN_ARGS`
