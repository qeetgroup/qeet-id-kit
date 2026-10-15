@echo off
rem Update STAGING to the candidate QA approved (the staging channel). Data is kept.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" update staging %*
exit /b %ERRORLEVEL%
