# Setup Checklist for CLI Bridge

Краткий чек-лист для запуска `cli-bridge`.

- [ ] **Установить зависимости** — выполни `npm install` в `services/cli-bridge`.
- [ ] **Настроить `.env`** — скопируй `.env.example` в `.env` и укажи `AGENT_QWEN_CMD=qwen`, `AGENT_QWEN_ARGS=--approval-mode yolo`.
- [ ] **Проверить PATH** — убедись, что команды `qwen` и `codex` доступны в терминале.
- [ ] **Запустить сервис** — выполни `npm run dev`, сервис запустится на `http://127.0.0.1:7071`.
- [ ] **Проверить здоровье** — выполни `Invoke-RestMethod http://127.0.0.1:7071/health` и убедись, что ответ `{"status":"ok"}`.
