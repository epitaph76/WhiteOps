# Stack Decision (MVP)

Дата фиксации: `2026-03-06`

## Принято

- Основной backend: `Node.js + TypeScript`
- Отдельная debug-прослойка CLI bridge: `Node.js + TypeScript`
- Транспорт для bridge MVP: `HTTP API` (расширяемо до `WebSocket`)
- Работа с локальными CLI-сессиями: `node-pty`
- Поддерживаемые агенты в первом MVP: `codex`, `qwen`

## Почему

- Быстрое прототипирование оркестрации без затрат на API в каждом цикле.
- Явный контроль над сессиями, таймаутами и техническими логами.
- Изоляция рисков: CLI-процессы живут в отдельном сервисе, не в публичном backend API.

## Реализация

- Сервис: `services/cli-bridge`
- Список агентов и команды задаются через env:
  - `AGENT_CODEX_CMD`, `AGENT_CODEX_ARGS`
  - `AGENT_QWEN_CMD`, `AGENT_QWEN_ARGS`
