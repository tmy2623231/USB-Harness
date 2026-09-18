@echo off
rem =============================================================================
rem  launch.bat - USB Harness launcher (Windows, double-click entry)
rem  Thin ASCII wrapper that calls scripts\launch-windows.ps1 (Chinese menu).
rem
rem  【为什么要做 ^C 拦截】
rem  cmd.exe 对批处理的 Ctrl+C 处理是「终止整个批处理」。在 Web 界面运行时按
rem  Ctrl+C，cmd 会弹出「终止批处理操作吗(Y/N)?」——即便答 n，也只是继续执行
rem  下一条命令，而 launch-windows.ps1 已经被中断，启动器整体退出，菜单没了。
rem
rem  做法：
rem    1) 顶层 `break off` —— 关闭 cmd 的 Ctrl+C 检查，不再弹那个 Y/N 提示；
rem    2) 循环重进 —— Ctrl+C 只打断当前这一轮 PowerShell，回到菜单由用户重选；
rem    3) 退出标记 —— 菜单里选「退出」时由 launch-windows.ps1 写
rem       .cache\launcher-exit.flag，循环看到标记才真正结束。
rem  只对启动器自身生效：PowerShell 子进程有自己的控制台进程组，Ctrl+C 照样能
rem  停掉它；显式传动作参数（web/cli/...）时只跑一次，行为不变。
rem =============================================================================
setlocal
cd /d "%~dp0"

where powershell >nul 2>nul
if errorlevel 1 goto :no_pwsh

rem 启动器本身不理会 Ctrl+C，避免 cmd 的「终止批处理操作吗(Y/N)?」把菜单一起带走
break off

:loop
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\launch-windows.ps1" %*
set RC=%errorlevel%

rem 显式传了动作（web/cli/setup/reset/status）时只跑一次，没有菜单可回
if not "%~1"=="" exit /b %RC%

rem 用户在菜单里选「退出」时 PowerShell 会写这个标记，此时真正结束；
rem 否则说明这轮 PowerShell 是被 Ctrl+C 打断的，回到菜单让用户重选
if exist "%~dp0.cache\launcher-exit.flag" (
    del "%~dp0.cache\launcher-exit.flag" >nul 2>nul
    exit /b 0
)

echo.
echo [提示] 已停止当前服务，返回菜单 ...
timeout /t 1 /nobreak >nul 2>nul
goto :loop

:no_pwsh
echo [ERROR] PowerShell not found. Windows 10/11 includes it by default.
pause
exit /b 1
