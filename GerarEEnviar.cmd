@echo off
rem Gera todos os instaladores e envia ao servidor
set "PS=powershell"
where pwsh >nul 2>nul
if not errorlevel 1 set "PS=pwsh"
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0Gerar.ps1" -Enviar %*
if errorlevel 1 (echo. & echo FALHOU. & pause & exit /b 1)
pause
