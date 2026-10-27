@echo off
setlocal enabledelayedexpansion
title PMD-faith setup - step 2 of 2: build the game files
cd /d "%~dp0"
echo.
echo  ================================================================
echo   PMD-faith setup - STEP 2 of 2: build the game files
echo  ================================================================
echo.

rem --- find tools that winget installed but Windows has not put on the PATH yet
for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\BrechtSanders.WinLibs*") do (
  if exist "%%D\mingw64\bin\gcc.exe" set "PATH=%%D\mingw64\bin;!PATH!"
)
for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\Gyan.FFmpeg*") do (
  for /d %%E in ("%%D\ffmpeg-*") do if exist "%%E\bin\ffmpeg.exe" set "PATH=%%E\bin;!PATH!"
)
if exist "%ProgramFiles%\Git\cmd\git.exe" set "PATH=%ProgramFiles%\Git\cmd;!PATH!"

set MISSING=
py -3 --version >nul 2>nul || set MISSING=!MISSING! Python
where git >nul 2>nul || set MISSING=!MISSING! Git
where ffmpeg >nul 2>nul || set MISSING=!MISSING! FFmpeg
where gcc >nul 2>nul || set MISSING=!MISSING! GCC
where g++ >nul 2>nul || set MISSING=!MISSING! G++
if not "!MISSING!"=="" (
  echo  These tools are missing:!MISSING!
  echo  Run SETUP_STEP1_install_tools.bat first, close its window, then run this file again.
  echo  If they are still missing, see SETUP.md, Troubleshooting.
  echo.
  pause
  exit /b 1
)
py -3 -c "import PIL, numpy" >nul 2>nul
if errorlevel 1 (
  echo  Installing the Python add-ons Pillow and NumPy...
  py -3 -m pip install --user --upgrade pillow numpy
)
echo  Tools: OK
echo.

rem --- ROM files (asked once; saved in build_config.json)
if exist build_config.json (
  echo  Your ROM files are already set up in build_config.json.
  choice /c YN /m "  Keep them? (N = pick the three files again)"
  if errorlevel 2 del build_config.json
  echo.
)
if not exist build_config.json (
  echo  A window opens three times. Pick:
  echo    1. your Red Rescue Team ROM          ^(.gba, US version^)
  echo    2. your Explorers of Sky ROM         ^(.nds, US version, NOT patched^)
  echo    3. your Explorers Remixed ROM        ^(.nds, Explorers of Sky with the Remixed patch^)
  echo.
  call :pick "1 of 3: your Pokemon Mystery Dungeon Red Rescue Team ROM (.gba)" "GBA ROM (*.gba)|*.gba|All files (*.*)|*.*" R1 || goto :cancelled
  call :pick "2 of 3: your Explorers of Sky ROM, the normal one (.nds)" "NDS ROM (*.nds)|*.nds|All files (*.*)|*.*" R2 || goto :cancelled
  call :pick "3 of 3: your Explorers Remixed ROM, the patched one (.nds)" "NDS ROM (*.nds)|*.nds|All files (*.*)|*.*" R3 || goto :cancelled
  py -3 -c "import json,os; json.dump({'red_rom':os.environ['R1'],'eos_rom':os.environ['R2'],'remix_rom':os.environ['R3']}, open('build_config.json','w'), indent=2)"
  echo  Saved your choices in build_config.json
  echo.
)

echo  The build now runs. It downloads about 2 GB the first time and takes
echo  1 to 3 hours, mostly music and sprites. You can use your PC meanwhile.
echo  If it stops, just run this file again: it continues where it stopped.
echo.
py -3 build_all.py
if errorlevel 1 (
  echo.
  echo  The build did not finish - see the message above.
  pause
  exit /b 1
)
echo.
echo  ================================================================
echo   Done! Now open the game in Godot (SETUP.md, part 4):
echo   start Godot 4.7.2, click Import, choose  game\project.godot
echo  ================================================================
echo.
pause
exit /b 0

:pick
set "%3="
for /f "usebackq delims=" %%F in (`powershell -NoProfile -STA -Command "Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Title = '%~1'; $d.Filter = '%~2'; if ($d.ShowDialog() -eq 'OK') { $d.FileName }"`) do set "%3=%%F"
if not defined %3 exit /b 1
echo    %~1
echo      -^> !%3!
exit /b 0

:cancelled
echo.
echo  No file chosen - nothing was changed. Run this file again when you have your ROMs ready.
pause
exit /b 1
