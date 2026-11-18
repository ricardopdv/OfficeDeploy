@echo off
rem Gera os instaladores em publicar\ (parametros: veja o inicio do Gerar.ps1)
set "PS=powershell"
where pwsh >nul 2>nul
if not errorlevel 1 set "PS=pwsh"
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0Gerar.ps1"  %*
if errorlevel 1 (echo. & echo FALHOU. & pause & exit /b 1)
pause
