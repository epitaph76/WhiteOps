# WhiteOps CLI Bridge (MVP)

CLI bridge — это локальная прослойка между оркестратором и CLI-агентами (`qwen`, `codex`).

Она умеет работать в двух режимах:

- `POST /runs` — one-shot (без интерактивного TUI), лучший вариант для оркестратора.
- `POST /sessions/...` — интерактивные PTY-сессии.

## Быстрый старт (PowerShell)

```powershell
cd C:\project\WhiteOps\services\cli-bridge
npm install
npm run dev
```

Сервис подгружает `./.env` автоматически при старте.

Проверка:

```powershell
Invoke-RestMethod http://127.0.0.1:7071/health
Invoke-RestMethod http://127.0.0.1:7071/agents
```

## Настройки `.env`

Основные переменные:

- `HOST`, `PORT` — адрес и порт bridge.
- `AGENT_CODEX_CMD`, `AGENT_CODEX_ARGS` — команда/аргументы Codex CLI.
- `AGENT_QWEN_CMD`, `AGENT_QWEN_ARGS` — команда/аргументы Qwen CLI.
- `DEFAULT_TIMEOUT_MS`, `MAX_TIMEOUT_MS` — лимиты выполнения.
- `DEFAULT_IDLE_MS` — idle-таймер для интерактивных `/sessions`.

Windows-нюанс:

- Можно указывать просто `qwen`/`codex`.
- Bridge сам попробует найти `.cmd/.exe/.bat` в `PATH`.

Рекомендуемый пример:

```env
PORT=7071
HOST=0.0.0.0

AGENT_CODEX_CMD=codex
AGENT_CODEX_ARGS=

AGENT_QWEN_CMD=qwen
AGENT_QWEN_ARGS=--approval-mode yolo

DEFAULT_TIMEOUT_MS=45000
DEFAULT_IDLE_MS=1200
MAX_TIMEOUT_MS=180000
```

`--approval-mode yolo` для Qwen нужен, если ты хочешь, чтобы агент реально выполнял действия с файлами.

## API

- `GET /health` — сервис жив.
- `GET /agents` — список агентов и их команд.
- `GET /sessions` — активные PTY-сессии.
- `POST /sessions` — создать сессию (`agentId`, опционально `cwd`).
- `POST /sessions/:sessionId/prompt` — отправить prompt в сессию.
- `DELETE /sessions/:sessionId` — закрыть сессию.
- `POST /runs` — one-shot запуск агента (`agentId`, `prompt`, опционально `cwd`, `timeoutMs`).

## Пример: отправить prompt в Qwen (one-shot)

```powershell
$body = @{
  agentId = "qwen"
  prompt = "Напиши hello world на Dart"
  cwd = "C:/project/WhiteOps"
  timeoutMs = 120000
} | ConvertTo-Json

$r = Invoke-RestMethod -Uri "http://127.0.0.1:7071/runs" -Method Post -Body $body -ContentType "application/json"
$r | Format-List timedOut,durationMs
$r.output
```

## Пример: создать файл `hello.txt` в `C:\project\WhiteOps`

```powershell
$body = @{
  agentId = "qwen"
  cwd = "C:/project/WhiteOps"
  timeoutMs = 180000
  prompt = "Создай файл hello.txt в текущей директории с точным содержимым: Привет мир. После создания ответь только DONE."
} | ConvertTo-Json

$r = Invoke-RestMethod -Uri "http://127.0.0.1:7071/runs" -Method Post -Body $body -ContentType "application/json"
$r.output

Get-Content C:\project\WhiteOps\hello.txt
```

## Пример: интерактивная сессия

```powershell
$session = Invoke-RestMethod -Uri "http://127.0.0.1:7071/sessions" -Method Post -Body (@{ agentId = "qwen"; cwd = "C:/project/WhiteOps" } | ConvertTo-Json) -ContentType "application/json"

$r = Invoke-RestMethod -Uri ("http://127.0.0.1:7071/sessions/" + $session.id + "/prompt") -Method Post -Body (@{ prompt = "Привет, это тест"; timeoutMs = 60000; idleMs = 3000 } | ConvertTo-Json) -ContentType "application/json"
$r.output

Invoke-RestMethod -Uri ("http://127.0.0.1:7071/sessions/" + $session.id) -Method Delete
```

## Частые проблемы

`Cannot create process, error code: 2`
- Команда агента не найдена. Проверь `AGENT_*_CMD` и `PATH`.
- На Windows можно указать полный путь, например `C:\Users\<user>\AppData\Roaming\npm\qwen.cmd`.

`Показывается только экран Qwen, ответа нет`
- Для оркестрации используй `POST /runs`, а не интерактивные `/sessions`.

`Агент отвечает текстом, но файл не создаёт`
- Для Qwen обычно нужен `AGENT_QWEN_ARGS=--approval-mode yolo`.
- Убедись, что задан правильный `cwd` в запросе.

`Изменил .env, но ничего не поменялось`
- Перезапусти `npm run dev`, чтобы env перечитался.
