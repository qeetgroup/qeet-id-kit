@echo off
rem Stop STAGING. Data is kept.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" stop staging %*
exit /b %ERRORLEVEL%
