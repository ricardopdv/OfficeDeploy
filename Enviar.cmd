@echo off
rem Envia publicar\ ao servidor de atualizacoes
set "PS=powershell"
where pwsh >nul 2>nul
if not errorlevel 1 set "PS=pwsh"
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0Enviar.ps1"  %*
if errorlevel 1 (echo. & echo FALHOU. & pause & exit /b 1)
pause
