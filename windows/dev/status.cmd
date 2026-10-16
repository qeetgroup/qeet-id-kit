@echo off
rem Show DEV: images, health and addresses.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" status dev %*
exit /b %ERRORLEVEL%
