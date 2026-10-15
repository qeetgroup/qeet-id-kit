@echo off
rem Go back to the previous STAGING candidate on this computer.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" rollback staging %*
exit /b %ERRORLEVEL%
