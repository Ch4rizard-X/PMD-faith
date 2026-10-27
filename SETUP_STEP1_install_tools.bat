@echo off
setlocal
title PMD-faith setup - step 1 of 2: install the tools
cd /d "%~dp0"
echo.
echo  ================================================================
echo   PMD-faith setup - STEP 1 of 2: install the free tools it needs
echo  ================================================================
echo.
echo  This installs, using Windows' own installer (winget):
echo    - Python        runs the build scripts
echo    - Git           downloads the community resources
echo    - FFmpeg        converts the music
echo    - GCC (WinLibs) compiles a few small helper programs
echo  and then the two Python add-ons Pillow and NumPy.
echo.
echo  Windows may ask "Do you want to allow this app to make changes?"
echo  for each one - click Yes. Already-installed tools are skipped.
echo.
pause

where winget >nul 2>nul
if errorlevel 1 (
  echo.
  echo  winget was not found. It comes with Windows 10 and 11 as "App Installer":
  echo  open the Microsoft Store, search for "App Installer", install or update it,
  echo  then run this file again.
  echo.
  pause
  exit /b 1
)

call :install Python.Python.3.12 "Python"
call :install Git.Git "Git"
call :install Gyan.FFmpeg "FFmpeg"
call :install BrechtSanders.WinLibs.POSIX.UCRT "GCC (WinLibs)"

echo.
echo  Installing the Python add-ons Pillow and NumPy...
py -3 -m pip install --user --upgrade pillow numpy
if errorlevel 1 (
  echo.
  echo  Could not install Pillow / NumPy yet. That is normal right after Python was installed:
  echo  close this window and run STEP 1 once more.
  echo.
  pause
  exit /b 1
)

echo.
echo  ================================================================
echo   Step 1 is done.
echo   IMPORTANT: close this window first (new programs only show up in
echo   new windows), then double-click SETUP_STEP2_build_game_files.bat
echo  ================================================================
echo.
pause
exit /b 0

:install
echo.
echo  --- %~2 ---
winget list --id %1 -e >nul 2>nul
if not errorlevel 1 (
  echo  already installed
  exit /b 0
)
winget install --id %1 -e --accept-source-agreements --accept-package-agreements
if errorlevel 1 echo  [!] %~2 did not install. You can install it by hand - see SETUP.md, part 1.
exit /b 0
