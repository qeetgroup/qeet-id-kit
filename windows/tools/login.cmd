@echo off
rem Sign in to GitHub Packages once, to download Qeet ID.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" login %*
exit /b %ERRORLEVEL%
