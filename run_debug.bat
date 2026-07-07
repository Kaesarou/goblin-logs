@echo off
setlocal

set "SCRIPT=C:\Projects\goblin-logs\archive_logs.bat"
set "DEBUG_LOG=C:\Projects\goblin-logs\debug_bat_output.log"

echo ==========================================================
echo Starting debug wrapper
echo Script: %SCRIPT%
echo Log: %DEBUG_LOG%
echo ==========================================================
echo.

echo ========================================================== >> "%DEBUG_LOG%"
echo DEBUG RUN - %date% %time% >> "%DEBUG_LOG%"
echo ========================================================== >> "%DEBUG_LOG%"

call "%SCRIPT%" >> "%DEBUG_LOG%" 2>&1

echo.
echo ==========================================================
echo Script exited with code %ERRORLEVEL%
echo Full output saved to:
echo %DEBUG_LOG%
echo ==========================================================
echo.
pause