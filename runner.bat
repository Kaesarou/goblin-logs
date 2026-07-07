@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ==========================================================
REM Earendil - hourly logs archival + git push
REM ==========================================================

REM Dossier source où Earendil écrit les logs
set "LOG_SOURCE=C:\Projects\earendil\data\logs"

REM Dossier racine du repo Git
set "GIT_REPO=C:\Projects\goblin-logs"

REM Fréquence : 3600 secondes = 1 heure
set "SLEEP_SECONDS=3600"

:loop
echo.
echo ==========================================================
echo [%date% %time%] Starting logs archive job
echo ==========================================================

REM Date du jour au format stable yyyy-MM-dd
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set "TODAY=%%i"

REM Timestamp compatible nom de commit
for /f "delims=" %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm-ss"') do set "TIMESTAMP=%%i"

set "DAY_DIR=%GIT_REPO%\%TODAY%"

REM Crée le dossier du jour s'il n'existe pas
if not exist "%DAY_DIR%" (
    echo Creating daily log directory: "%DAY_DIR%"
    mkdir "%DAY_DIR%"
)

REM Vérifie le dossier source
if not exist "%LOG_SOURCE%" (
    echo ERROR: LOG_SOURCE does not exist: "%LOG_SOURCE%"
    goto wait_next
)

REM Vérifie le repo Git
if not exist "%GIT_REPO%\.git" (
    echo ERROR: GIT_REPO is not a Git repository: "%GIT_REPO%"
    goto wait_next
)

echo Moving logs from "%LOG_SOURCE%" to "%DAY_DIR%"

REM Déplace tous les fichiers du dossier source vers le dossier du jour.
REM /MOV = déplace les fichiers après copie réussie.
REM /R:2 /W:5 = 2 tentatives, 5 secondes d'attente.
REM Important : les fichiers actuellement verrouillés par le bot peuvent être ignorés.
robocopy "%LOG_SOURCE%" "%DAY_DIR%" *.* /MOV /R:2 /W:5 /NP

REM Robocopy retourne 0 à 7 pour succès / succès partiel non bloquant.
if %ERRORLEVEL% GEQ 8 (
    echo ERROR: Robocopy failed with errorlevel %ERRORLEVEL%
    goto wait_next
)

cd /d "%GIT_REPO%"

REM Vérifie s'il y a quelque chose à commit
git status --porcelain "." > "%TEMP%\earendil_git_status.txt"

for %%A in ("%TEMP%\earendil_git_status.txt") do set "STATUS_SIZE=%%~zA"

if "%STATUS_SIZE%"=="0" (
    echo No log changes to commit.
    del "%TEMP%\earendil_git_status.txt" >nul 2>&1
    goto wait_next
)

del "%TEMP%\earendil_git_status.txt" >nul 2>&1

echo Git add...
git add "."

echo Git commit...
git commit -m "logs - %TIMESTAMP%"

if errorlevel 1 (
    echo WARNING: git commit failed or nothing to commit.
    goto wait_next
)

echo Git push...
git push

if errorlevel 1 (
    echo ERROR: git push failed.
    goto wait_next
)

echo Done: logs pushed successfully.

:wait_next
echo Waiting %SLEEP_SECONDS% seconds before next run...
timeout /t %SLEEP_SECONDS% /nobreak >nul
goto loop