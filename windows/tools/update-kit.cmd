@echo off
rem Install a newer Qeet ID Kit next to this one.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" update-kit %*
exit /b %ERRORLEVEL%
