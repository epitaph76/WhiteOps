@echo off
setlocal EnableExtensions

cd /d "%~dp0"
set "ROOT=%~dp0"
set "CLEAN_MODE=0"
if /I "%~1"=="--clean" set "CLEAN_MODE=1"
if /I "%~1"=="/clean" set "CLEAN_MODE=1"

echo.
echo [WhiteOps] Starting full local stack...
echo [WhiteOps] Root: %ROOT%
echo.

where npm >nul 2>nul
if errorlevel 1 (
  echo [WhiteOps] ERROR: npm not found in PATH.
  pause
  exit /b 1
)

where flutter >nul 2>nul
if errorlevel 1 (
  echo [WhiteOps] ERROR: flutter not found in PATH.
  pause
  exit /b 1
)

if not exist "%ROOT%services\orchestrator\.env" (
  if exist "%ROOT%services\orchestrator\.env.example" (
    copy "%ROOT%services\orchestrator\.env.example" "%ROOT%services\orchestrator\.env" >nul
    echo [WhiteOps] Created services\orchestrator\.env from .env.example
  )
)

if not exist "%ROOT%services\cli-bridge\.env" (
  if exist "%ROOT%services\cli-bridge\.env.example" (
    copy "%ROOT%services\cli-bridge\.env.example" "%ROOT%services\cli-bridge\.env" >nul
    echo [WhiteOps] Created services\cli-bridge\.env from .env.example
  )
)

if not exist "%ROOT%services\cli-bridge\node_modules" (
  echo [WhiteOps] Installing cli-bridge dependencies...
  pushd "%ROOT%services\cli-bridge"
  call npm install
  if errorlevel 1 (
    echo [WhiteOps] ERROR: npm install failed in services\cli-bridge
    popd
    pause
    exit /b 1
  )
  popd
)

if not exist "%ROOT%services\orchestrator\node_modules" (
  echo [WhiteOps] Installing orchestrator dependencies...
  pushd "%ROOT%services\orchestrator"
  call npm install
  if errorlevel 1 (
    echo [WhiteOps] ERROR: npm install failed in services\orchestrator
    popd
    pause
    exit /b 1
  )
  popd
)

set "BRIDGE_HEALTH_URL=http://127.0.0.1:7071/health"
set "ORCH_HEALTH_URL=http://127.0.0.1:7081/health"
set "MAX_HEALTH_RETRIES=30"

if "%CLEAN_MODE%"=="1" (
  call :clean_existing
)

call :check_health "%BRIDGE_HEALTH_URL%"
if "%HEALTH_OK%"=="1" (
  echo [WhiteOps] cli-bridge already running on 7071.
) else (
  echo [WhiteOps] Starting cli-bridge...
  start "WhiteOps cli-bridge" cmd /k "cd /d ""%ROOT%services\cli-bridge"" && npm run dev"
)

call :check_health "%ORCH_HEALTH_URL%"
if "%HEALTH_OK%"=="1" (
  echo [WhiteOps] orchestrator already running on 7081.
) else (
  echo [WhiteOps] Starting orchestrator...
  start "WhiteOps orchestrator" cmd /k "cd /d ""%ROOT%services\orchestrator"" && npm run dev"
)

echo [WhiteOps] Waiting for cli-bridge health...
call :wait_health "%BRIDGE_HEALTH_URL%" %MAX_HEALTH_RETRIES%
if not "%HEALTH_OK%"=="1" (
  echo [WhiteOps] ERROR: cli-bridge did not become healthy in time.
  pause
  exit /b 1
)

echo [WhiteOps] Waiting for orchestrator health...
call :wait_health "%ORCH_HEALTH_URL%" %MAX_HEALTH_RETRIES%
if not "%HEALTH_OK%"=="1" (
  echo [WhiteOps] ERROR: orchestrator did not become healthy in time.
  pause
  exit /b 1
)

echo [WhiteOps] Starting Flutter desktop...
start "WhiteOps frontend" cmd /k "cd /d ""%ROOT%apps\orchestrator_desktop"" && flutter pub get && flutter run -d windows"

echo.
echo [WhiteOps] Done. Three windows should now be running:
echo   1) cli-bridge
echo   2) orchestrator
echo   3) Flutter desktop frontend
echo.
echo [WhiteOps] If something failed, check terminal windows and .run-logs.
echo.
pause
exit /b 0

:clean_existing
echo [WhiteOps] Clean mode enabled. Stopping previous WhiteOps processes...
taskkill /FI "WINDOWTITLE eq WhiteOps cli-bridge" /T /F >nul 2>nul
taskkill /FI "WINDOWTITLE eq WhiteOps orchestrator" /T /F >nul 2>nul
taskkill /FI "WINDOWTITLE eq WhiteOps frontend" /T /F >nul 2>nul

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=(Resolve-Path '%ROOT%').Path; " ^
  "$procs=Get-CimInstance Win32_Process | Where-Object { " ^
  "  $_.CommandLine -and $_.CommandLine -like ('*' + $root + '*') -and (" ^
  "    $_.Name -in @('node.exe','dart.exe','dartaotruntime.exe','dartvm.exe') -or " ^
  "    $_.CommandLine -match 'flutter run|tsx|services\\\\orchestrator|services\\\\cli-bridge|orchestrator_desktop'" ^
  "  ) " ^
  "}; " ^
  "foreach ($p in $procs) { try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop } catch {} }"

timeout /t 1 /nobreak >nul
exit /b 0

:check_health
set "HEALTH_OK=0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { $r = Invoke-WebRequest -UseBasicParsing -Uri '%~1' -TimeoutSec 2; if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) { exit 0 } else { exit 1 } } catch { exit 1 }"
if not errorlevel 1 set "HEALTH_OK=1"
exit /b 0

:wait_health
set "HEALTH_OK=0"
set /a "_retries=%~2"
if "%_retries%"=="" set /a "_retries=20"
:wait_health_loop
call :check_health "%~1"
if "%HEALTH_OK%"=="1" exit /b 0
set /a "_retries=%_retries%-1"
if %_retries% LEQ 0 exit /b 0
timeout /t 1 /nobreak >nul
goto :wait_health_loop
