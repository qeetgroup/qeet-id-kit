@echo off
rem Show TEST: version, health and addresses.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" status test %*
exit /b %ERRORLEVEL%
