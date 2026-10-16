@echo off
rem DELETE DEV's data and secrets and start it fresh (asks first).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" reset dev %*
exit /b %ERRORLEVEL%
