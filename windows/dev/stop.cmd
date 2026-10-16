@echo off
rem Stop DEV. Data is kept.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" stop dev %*
exit /b %ERRORLEVEL%
