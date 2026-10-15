@echo off
rem Show STAGING logs: [server|login|console|website|docs|db|mail|edge] [--follow] [--tail N].
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" logs --env staging %*
exit /b %ERRORLEVEL%
