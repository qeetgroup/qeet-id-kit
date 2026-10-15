@echo off
rem Go back to the previous TEST candidate on this computer.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" rollback test %*
exit /b %ERRORLEVEL%
