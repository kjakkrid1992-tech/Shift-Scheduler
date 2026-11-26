@echo off
cd /d "%~dp0"
node scripts\start-v8-local.cjs
if errorlevel 1 pause
