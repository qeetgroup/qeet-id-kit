@echo off
rem Start (or update) STAGING, where Product/UAT validates the candidate QA approved.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" start staging %*
exit /b %ERRORLEVEL%
