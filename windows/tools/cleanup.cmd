@echo off
rem Remove old candidate images (keeps current and previous).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" cleanup %*
exit /b %ERRORLEVEL%
