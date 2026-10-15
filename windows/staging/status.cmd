@echo off
rem Show STAGING: version, health and addresses.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" status staging %*
exit /b %ERRORLEVEL%
