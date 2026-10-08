@echo off
setlocal
title golem-next - Demo MI_1.MID

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-mi1-demo.ps1" %*
set "DEMO_RESULT=%ERRORLEVEL%"

if not "%DEMO_RESULT%"=="0" (
    echo.
    echo La demo no pudo iniciarse. Revisa el mensaje anterior.
    pause
)

endlocal & exit /b %DEMO_RESULT%
