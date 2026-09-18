@echo off
rem =============================================================================
rem  launch.bat - USB Harness launcher (Windows, double-click entry)
rem  Thin ASCII wrapper that calls scripts\launch-windows.ps1 (Chinese menu).
rem
rem  Why the Ctrl+C handling (full rationale: scripts\launch-windows.ps1 header):
rem    - Plain wrapper: Ctrl+C makes cmd ask "Terminate batch job (Y/N)?" and
rem      even answering N leaves a dead launcher (wrapped script already gone).
rem    - `break off` disables that prompt; the :loop below re-enters the menu
rem      after the interrupted round dies.
rem    - Exit flag .cache\launcher-exit.flag is written by the script menu when
rem      the user picks "Exit" - only then does the loop really end.
rem    - With explicit action args (web/cli/...) it runs once, no loop.
rem
rem  NOTE: KEEP THIS FILE ASCII-ONLY. cmd parses batch files byte-wise in the
rem  OEM/ANSI codepage (GBK on zh-CN systems). UTF-8 Chinese comments here get
rem  mis-split and parts of them are EXECUTED as commands (garbled "is not
rem  recognized as an internal or external command" errors at startup).
rem =============================================================================
setlocal
cd /d "%~dp0"

where powershell >nul 2>nul
if errorlevel 1 goto :no_pwsh

rem The launcher itself ignores Ctrl+C: no Y/N prompt, and an interrupted round
rem falls back to the menu instead of killing the whole launcher.
break off

:loop
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\launch-windows.ps1" %*
set RC=%errorlevel%

rem Explicit action (web/cli/setup/reset/status): run once, no menu to return to
if not "%~1"=="" exit /b %RC%

rem "Exit" picked in the menu: the script wrote the flag - really end now.
rem Otherwise this round was interrupted by Ctrl+C: go back to the menu.
if exist "%~dp0.cache\launcher-exit.flag" (
    del "%~dp0.cache\launcher-exit.flag" >nul 2>nul
    exit /b 0
)

echo.
echo [INFO] Service stopped. Back to menu ...
timeout /t 1 /nobreak >nul 2>nul
goto :loop

:no_pwsh
echo [ERROR] PowerShell not found. Windows 10/11 includes it by default.
pause
exit /b 1
