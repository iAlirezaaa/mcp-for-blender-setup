@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1" %*
set "rc=%ERRORLEVEL%"
echo.
if not "%rc%"=="0" echo Update FAILED with exit code %rc%.
echo Press any key to close this window...
pause >nul
exit /b %rc%
