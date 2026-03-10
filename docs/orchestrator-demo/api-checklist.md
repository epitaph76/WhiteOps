# API Checklist for POST /runs

Краткий чек-лист для smoke-тестирования `POST /runs`.

- [ ] **Тело запроса** — JSON с `agentId`, `prompt`, `cwd`, `timeoutMs`.
- [ ] **Отправка** — `Invoke-RestMethod -Method Post -Uri http://127.0.0.1:7071/runs`.
- [ ] **Ответ** — проверка полей `output` (string), `timedOut` (boolean), `durationMs` (number).
- [ ] **Вывод** — чтение `output`, агент выполнил задачу.
- [ ] **Артефакты** — проверка созданных файлов в `cwd`.
