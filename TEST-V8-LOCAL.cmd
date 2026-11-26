@echo off
cd /d "%~dp0"
node scripts\test-v8-local.cjs --full
pause
