@echo off
title Earendil Logs Archiver
setlocal EnableExtensions EnableDelayedExpansion

REM ==========================================================
REM Earendil - hourly logs archival + git push
REM ==========================================================

REM Dossier source où Earendil écrit les logs.
REM Tu peux surcharger cette valeur avant lancement avec:
REM set LOG_SOURCE=C:\autre\chemin\data\logs
if not defined LOG_SOURCE set "LOG_SOURCE=C:\Projects\earendil\data\logs"

REM Dossier racine du repo Git: par défaut, le dossier où se trouve ce script.
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%.") do set "GIT_REPO=%%~fI"

REM Les logs archivés sont copiés dans goblin-logs\logs\YYYY-MM-DD.
set "ARCHIVE_ROOT=%GIT_REPO%\logs"

REM Script PowerShell de split.
set "SPLIT_SCRIPT=%GIT_REPO%\split_large_logs.ps1"

REM Fréquence : 3600 secondes = 1 heure.
if not defined SLEEP_SECONDS set "SLEEP_SECONDS=3600"

REM Taille max cible par fichier : 70 MB environ, sous la limite GitHub de 100 MB.
set "MAX_FILE_BYTES=73400320"

:loop
echo.
echo ==========================================================
echo [%date% %time%] Starting logs archive job
echo ==========================================================

REM Date du jour au format stable yyyy-MM-dd.
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set "TODAY=%%i"

REM Timestamp compatible nom de commit.
for /f "delims=" %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm-ss"') do set "TIMESTAMP=%%i"

set "DAY_DIR=%ARCHIVE_ROOT%\%TODAY%"

REM Vérifie le dossier source.
if not exist "%LOG_SOURCE%" (
    echo ERROR: LOG_SOURCE does not exist: "%LOG_SOURCE%"
    goto wait_next
)

REM Vérifie le repo Git.
if not exist "%GIT_REPO%\.git" (
    echo ERROR: GIT_REPO is not a Git repository: "%GIT_REPO%"
    goto wait_next
)

REM Vérifie le script de split.
if not exist "%SPLIT_SCRIPT%" (
    echo ERROR: SPLIT_SCRIPT does not exist: "%SPLIT_SCRIPT%"
    goto wait_next
)

REM Crée le dossier logs et le dossier du jour s'ils n'existent pas.
if not exist "%ARCHIVE_ROOT%" (
    echo Creating archive root: "%ARCHIVE_ROOT%"
    mkdir "%ARCHIVE_ROOT%"
)

if not exist "%DAY_DIR%" (
    echo Creating daily log directory: "%DAY_DIR%"
    mkdir "%DAY_DIR%"
)

echo Copying logs from "%LOG_SOURCE%" to "%DAY_DIR%"

REM Copie snapshot des logs sans les supprimer côté Earendil.
REM /E copie aussi les sous-dossiers éventuels.
REM /R:2 /W:5 = 2 tentatives, 5 secondes d'attente.
REM Robocopy retourne 0 à 7 pour succès / succès partiel non bloquant.
robocopy "%LOG_SOURCE%" "%DAY_DIR%" *.* /E /R:2 /W:5 /NP

if %ERRORLEVEL% GEQ 8 (
    echo ERROR: Robocopy failed with errorlevel %ERRORLEVEL%
    goto wait_next
)

echo Splitting large files over 70 MB in "%DAY_DIR%"...

powershell -NoProfile -ExecutionPolicy Bypass -File "%SPLIT_SCRIPT%" -Root "%DAY_DIR%" -MaxBytes %MAX_FILE_BYTES%

if errorlevel 1 (
    echo ERROR: large file splitting failed.
    goto wait_next
)

cd /d "%GIT_REPO%"

REM Sécurité : vérifie qu'aucun fichier > 100 MB ne va être committé.
echo Checking for files still over GitHub 100 MB limit...

for /f "delims=" %%i in ('powershell -NoProfile -Command "Get-ChildItem -Path . -Recurse -File | Where-Object { $_.Length -gt 100MB -and $_.FullName -notmatch '\\.git\\' } | Select-Object -ExpandProperty FullName"') do (
    echo ERROR: File still too large for GitHub: %%i
    echo Commit aborted.
    goto wait_next
)

REM Vérifie s'il y a quelque chose à commit.
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
