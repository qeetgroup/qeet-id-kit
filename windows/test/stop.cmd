@echo off
rem Stop TEST. Data is kept.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" stop test %*
exit /b %ERRORLEVEL%
