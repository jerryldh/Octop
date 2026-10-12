@echo off
chcp 936 >nul
title Atour DataAgent - stop
setlocal enabledelayedexpansion

set "PORT=8088"
set "KILLED="
set "COUNT=0"

echo ============================================================
echo   Atour DataAgent - stop (port %PORT%)
echo ============================================================
echo.

for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%PORT% " ^| findstr LISTENING') do (
  echo !KILLED! | findstr /c:",%%a," >nul
  if errorlevel 1 (
    set "KILLED=!KILLED!,%%a,"
    echo   [stop] PID %%a
    taskkill /PID %%a /T /F >nul 2>&1
    if !errorlevel!==0 (
      set /a COUNT+=1
      echo          ^> ok
    ) else (
      echo          ^> failed ^(need admin?^)
    )
  )
)

if "!COUNT!"=="0" (
  echo   no running service found on port %PORT%
) else (
  echo   stopped !COUNT! process^(es^)
)

ping -n 3 127.0.0.1 >nul 2>&1
