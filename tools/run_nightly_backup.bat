@echo off
REM =========================================================================
REM MIPS ERP - Windows Scheduled Nightly Backup Script
REM Automatically runs nightly_export.py and stores archives in backups/
REM =========================================================================

cd /d "%~dp0\.."

echo [%DATE% %TIME%] Starting MIPS ERP Nightly Export... >> backups\nightly_backup.log 2>&1

python tools\nightly_export.py --output-dir backups --retention-days 30 >> backups\nightly_backup.log 2>&1

if %ERRORLEVEL% EQU 0 (
    echo [%DATE% %TIME%] Nightly Export completed successfully. >> backups\nightly_backup.log
) else (
    echo [%DATE% %TIME%] ERROR: Nightly Export failed with exit code %ERRORLEVEL%. >> backups\nightly_backup.log
)
