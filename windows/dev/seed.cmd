@echo off
rem REPLACE DEV's data with the server's demo data (asks first).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" seed dev %*
exit /b %ERRORLEVEL%
