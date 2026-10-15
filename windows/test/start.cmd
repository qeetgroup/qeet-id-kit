@echo off
rem Start (or update) TEST, where QA tests the current release candidate.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" start test %*
exit /b %ERRORLEVEL%
