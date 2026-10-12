@echo off
chcp 936 >nul
title Atour DataAgent - source (8088)
setlocal

set "ROOT=D:\hub\codeHub\Octop"
set "PY=%USERPROFILE%\.octop\venv\Scripts\python.exe"
set "PORT=8088"

echo ============================================================
echo   Atour DataAgent - run from source
echo ============================================================
echo   Root   : %ROOT%
echo   Python : %PY%
echo   Port   : %PORT%
echo   Data   : %USERPROFILE%\.octop
echo ------------------------------------------------------------

if not exist "%PY%" (
  echo [ERROR] python not found: %PY%
  pause & exit /b 1
)
if not exist "%ROOT%\src\octop\__init__.py" (
  echo [ERROR] source not found: %ROOT%\src\octop
  pause & exit /b 1
)

set "PORT_PID="
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%PORT% " ^| findstr LISTENING') do set "PORT_PID=%%a"
if defined PORT_PID (
  echo [WARN] port %PORT% is already in use by PID %PORT_PID%
  echo        run stop-atour.bat first, or change PORT above
  pause & exit /b 0
)

rem --- make source win over site-packages (editable-style, no reinstall) ---
set "PYTHONPATH=%ROOT%\src"

cd /d "%ROOT%"
"%PY%" -m octop run --host 0.0.0.0 --port %PORT%

echo.
echo [EXIT] service stopped, code=%errorlevel%
pause
