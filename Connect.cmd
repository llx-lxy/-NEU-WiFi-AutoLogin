@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0NEU-WiFi-AutoLogin.ps1" -Action Connect
echo.
echo This window will close in 10 seconds.
timeout /t 10 /nobreak >nul
