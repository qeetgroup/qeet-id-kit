@echo off
rem Stop every environment and the local edge. Data is kept.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" stop all %*
exit /b %ERRORLEVEL%
