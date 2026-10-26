@echo off
cd /d "%~dp0"
call build_thor.bat debug > "%~dp0build_thor_log.txt" 2>&1
echo === DONE === >> "%~dp0build_thor_log.txt"
