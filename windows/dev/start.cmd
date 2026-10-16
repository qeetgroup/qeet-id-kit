@echo off
rem Start DEV: --build builds your working trees; --image <component>=<ref> picks an image;
rem with neither, DEV runs the images it ran last time.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\core\scripts\QeetIdKit.ps1" start dev %*
exit /b %ERRORLEVEL%
