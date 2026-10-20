@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0NEU-WiFi-AutoLogin.ps1" -Action Remove
pause
