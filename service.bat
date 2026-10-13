@echo off
chcp 936 >nul
title Atour DataAgent - service
setlocal enabledelayedexpansion

rem ============================================================
rem  Atour DataAgent  服务管理  (Windows)
rem  用法:  service.bat  [start ^| stop ^| restart ^| status ^| logs]
rem  特性:  以源码 src 覆盖 site-packages 运行，日志落到数据目录
rem ============================================================

set "ROOT=D:\hub\codeHub\Octop"
set "PY=%USERPROFILE%\.octop\venv\Scripts\python.exe"
set "OCTOP_HOME=%USERPROFILE%\.octop"
set "LOGDIR=%OCTOP_HOME%\logs"
set "LOG=%LOGDIR%\octop-console.log"
set "RUNNER=%LOGDIR%\run-octop.bat"
set "PORT=8088"
set "HOST=127.0.0.1"

rem --- 参数归一化，兼容 -start / --start / /start ---
set "CMD=%~1"
for /f "tokens=* delims=/-" %%a in ("%CMD%") do set "CMD=%%a"

if /i "%CMD%"=="start"   goto do_start
if /i "%CMD%"=="stop"    goto do_stop
if /i "%CMD%"=="restart" goto do_restart
if /i "%CMD%"=="status"  goto do_status
if /i "%CMD%"=="logs"    goto do_logs
goto do_help

rem ============================================================
rem  公共子过程
rem ============================================================

:find_pid
set "PID_FOUND="
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%PORT% " ^| findstr LISTENING') do (
  if not defined PID_FOUND set "PID_FOUND=%%a"
)
exit /b 0

:write_runner
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1
> "%RUNNER%" echo @echo off
>> "%RUNNER%" echo chcp 936 ^>nul
>> "%RUNNER%" echo cd /d "%ROOT%"
>> "%RUNNER%" echo set "PYTHONPATH=%ROOT%\src"
>> "%RUNNER%" echo set "OCTOP_HOME=%OCTOP_HOME%"
>> "%RUNNER%" echo set "HTTP_PROXY="
>> "%RUNNER%" echo set "HTTPS_PROXY="
>> "%RUNNER%" echo set "http_proxy="
>> "%RUNNER%" echo set "https_proxy="
>> "%RUNNER%" echo set "NO_PROXY=*"
>> "%RUNNER%" echo "%PY%" -m octop run --host 0.0.0.0 --port %PORT% ^> "%LOG%" 2^>^&1
exit /b 0

:wait_up
set /a "TRIES=%~1"
:wait_up_loop
call :find_pid
if defined PID_FOUND exit /b 0
set /a TRIES-=1
if !TRIES! LEQ 0 exit /b 1
ping -n 2 127.0.0.1 >nul 2>&1
goto wait_up_loop

:wait_down
set /a "TRIES=%~1"
:wait_down_loop
call :find_pid
if not defined PID_FOUND exit /b 0
set /a TRIES-=1
if !TRIES! LEQ 0 exit /b 1
ping -n 2 127.0.0.1 >nul 2>&1
goto wait_down_loop

:probe_http
set "CODE="
for /f "delims=" %%c in ('curl -s -o NUL -w "%%{http_code}" "http://%HOST%:%PORT%/api/health" 2^>nul') do set "CODE=%%c"
if "!CODE!"=="000" set "CODE="
if defined CODE (
  echo   [健康] HTTP !CODE!   http://%HOST%:%PORT%/api/health
) else (
  echo   [健康] 未能探测到 HTTP 响应
)
exit /b 0

rem ============================================================
rem  start
rem ============================================================

:do_start
echo ============================================================
echo   Atour DataAgent - start
echo ============================================================
echo   源码根目录 : %ROOT%
echo   Python     : %PY%
echo   数据目录   : %OCTOP_HOME%
echo   监听地址   : %HOST%:%PORT%
echo   控制台日志 : %LOG%
echo ------------------------------------------------------------

call :find_pid
if defined PID_FOUND (
  echo   [提示] 服务已在运行 PID !PID_FOUND! 无需重复启动
  exit /b 0
)

if not exist "%PY%" goto err_python
if not exist "%ROOT%\src\octop\__init__.py" goto err_source

echo   [启动] 正在后台启动服务 ...
call :write_runner
powershell -NoProfile -Command "Start-Process -FilePath '%RUNNER%' -WindowStyle Hidden" >nul 2>&1
if not errorlevel 1 goto start_wait
echo   [降级] 未检测到可用 PowerShell 改用 start /min 启动
start "Atour DataAgent" /min "%RUNNER%"

:start_wait
call :wait_up 30
if errorlevel 1 goto err_timeout

call :find_pid
echo   [成功] 服务已启动 PID !PID_FOUND!
call :probe_http
exit /b 0

:err_python
echo   [错误] 未找到 Python: %PY%
echo          请先执行安装 install.bat 或 scripts\install.sh
exit /b 1

:err_source
echo   [错误] 未找到源码目录: %ROOT%\src\octop
echo          请确认脚本顶部 ROOT 变量指向正确的仓库路径
exit /b 1

:err_timeout
echo   [失败] 服务在 30 秒内未监听端口 %PORT%
echo          请查看日志: %LOG%
exit /b 1

rem ============================================================
rem  stop
rem ============================================================

:do_stop
echo ============================================================
echo   Atour DataAgent - stop
echo ============================================================
echo.
set "KILLED="
set "COUNT=0"
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%PORT% " ^| findstr LISTENING') do (
  echo !KILLED! | findstr /c:",%%a," >nul
  if errorlevel 1 (
    set "KILLED=!KILLED!,%%a,"
    echo   [停止] PID %%a
    taskkill /PID %%a /T /F >nul 2>&1
    if !errorlevel!==0 (
      set /a COUNT+=1
      echo          ^> 已结束
    ) else (
      echo          ^> 失败 可能需管理员权限
    )
  )
)
if "!COUNT!"=="0" (
  echo   未发现运行中的服务 端口 %PORT% 无监听
) else (
  echo   已停止 !COUNT! 个进程
)
exit /b 0

rem ============================================================
rem  restart
rem ============================================================

:do_restart
echo ============================================================
echo   Atour DataAgent - restart
echo ============================================================
echo.
call :do_stop
echo.
echo   [等待] 等待端口 %PORT% 释放 ...
call :wait_down 15
if errorlevel 1 echo   [警告] 端口 %PORT% 仍被占用 尝试继续启动
echo.
call :do_start
exit /b %errorlevel%

rem ============================================================
rem  status
rem ============================================================

:do_status
echo ============================================================
echo   Atour DataAgent - status
echo ============================================================
echo   运行模式   : Windows 手动托管 无服务管理器
echo   源码根目录 : %ROOT%
echo   数据目录   : %OCTOP_HOME%
echo   监听地址   : %HOST%:%PORT%
echo   控制台日志 : %LOG%
echo ------------------------------------------------------------
call :find_pid
if defined PID_FOUND (
  echo   service : RUNNING   PID !PID_FOUND!
  call :probe_http
) else (
  echo   service : STOPPED   端口 %PORT% 无监听
)
exit /b 0

rem ============================================================
rem  logs
rem ============================================================

:do_logs
if not exist "%LOG%" (
  echo   日志文件尚未生成: %LOG%
  exit /b 0
)
echo   正在跟踪日志 %LOG%   按 Ctrl+C 退出
echo ------------------------------------------------------------
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG%' -Wait -Tail 40"
exit /b 0

rem ============================================================
rem  help
rem ============================================================

:do_help
echo ============================================================
echo   Atour DataAgent  服务管理  Windows
echo ============================================================
echo   用法:
echo     service.bat start      启动服务 后台运行并写日志
echo     service.bat stop       停止服务
echo     service.bat restart    重启服务
echo     service.bat status     查看运行状态与健康检查
echo     service.bat logs       跟踪控制台日志
echo.
echo   兼容写法: -start / --start / /start
echo.
echo   配置:
echo     源码根目录 : %ROOT%
echo     数据目录   : %OCTOP_HOME%
echo     监听端口   : %PORT%
echo     日志文件   : %LOG%
echo ============================================================
pause
exit /b 0
