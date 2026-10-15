@echo off
rem Check this computer: Docker, memory, disk, port 80, sign-in.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" doctor %*
exit /b %ERRORLEVEL%
