@echo off
rem Update TEST to the newest release candidate. Data is kept.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" update test %*
exit /b %ERRORLEVEL%
