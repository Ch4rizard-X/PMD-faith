@echo off
rem ------------------------------------------------------------------------------------------------
rem  build_thor.bat - Android APK with AYN Thor dual-screen support (ThorScreen v2 Android plugin).
rem    1) builds thor_plugin\ (Gradle) -> game\addons\thor_screen\bin\{debug,release}\ThorScreen-*.aar
rem    2) installs Godot's Android Gradle build template into game\android\build (headless)
rem    3) exports the "Android" preset (Gradle build) to game\build\PMDRed.apk
rem  Usage: build_thor.bat            (release export, the preset's keystore)
rem         build_thor.bat debug      (debug export, Godot's debug keystore)
rem  Override the Godot path with:  set GODOT=C:\path\to\Godot_v4.7.2-stable_win64_console.exe
rem ------------------------------------------------------------------------------------------------
setlocal EnableExtensions
set "ROOT=%~dp0"
set "MODE=release"
if /I "%~1"=="debug" set "MODE=debug"

rem Gradle 8.11 can't run on Java 25 (Android Studio's bundled JBR), so use a portable JDK 21.
set "JAVA_HOME=%ROOT%jdk21"
if not exist "%JAVA_HOME%\bin\java.exe" (
  echo Downloading portable Temurin JDK 21...
  curl -L --fail -o "%ROOT%jdk21.zip" "https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse"
  if errorlevel 1 ( echo *** JDK download failed. & exit /b 1 )
  if exist "%ROOT%jdk21_tmp" rmdir /s /q "%ROOT%jdk21_tmp"
  mkdir "%ROOT%jdk21_tmp"
  tar -xf "%ROOT%jdk21.zip" -C "%ROOT%jdk21_tmp"
  for /d %%D in ("%ROOT%jdk21_tmp\jdk-21*") do move "%%~fD" "%JAVA_HOME%" >nul
  rmdir /s /q "%ROOT%jdk21_tmp"
  del "%ROOT%jdk21.zip"
)
rem make Godot's own Gradle export use the same JDK
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%set_godot_java.ps1" "%JAVA_HOME%"
if not defined ANDROID_HOME set "ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk"
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
set "PATH=%JAVA_HOME%\bin;%PATH%"

if not defined GODOT (
  if exist "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" (
    set "GODOT=C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
  ) else (
    for %%F in ("C:\Godot\Godot_v4.7.2*console*.exe" "C:\Godot\Godot_v4.7.2*.exe") do if not defined GODOT set "GODOT=%%~fF"
  )
)
if not defined GODOT (
  echo Godot 4.7.2 not found in C:\Godot - set GODOT to the editor .exe and run again.
  exit /b 1
)
if not exist "%JAVA_HOME%\bin\java.exe" (
  echo JDK not found at "%JAVA_HOME%".
  exit /b 1
)
echo Godot: %GODOT%

rem ---- 1) ThorScreen AAR (Gradle wrapper; first run downloads Gradle 8.11.1, AGP and godot-lib 4.7.2.stable)
echo sdk.dir=%ANDROID_HOME:\=\\%> "%ROOT%android\thor_plugin\local.properties"
pushd "%ROOT%android\thor_plugin"
call gradlew.bat --no-daemon :plugin:copyAARsToAddon
if errorlevel 1 (
  popd
  echo *** ThorScreen plugin build failed.
  exit /b 1
)
popd
if not exist "%ROOT%game\addons\thor_screen\bin\release\ThorScreen-release.aar" (
  echo *** ThorScreen-release.aar missing after the build.
  exit /b 1
)

rem ---- 2) + 3) import, install the Android build template, export (Gradle build)
pushd "%ROOT%game"
"%GODOT%" --headless --path . --import
if not exist "build" mkdir build
if "%MODE%"=="debug" (
  "%GODOT%" --headless --path . --install-android-build-template --export-debug "Android Thor" "build/PMDRed-Thor.apk"
) else (
  "%GODOT%" --headless --path . --install-android-build-template --export-release "Android Thor" "build/PMDRed-Thor.apk"
)
set "ERR=%ERRORLEVEL%"
popd
if not "%ERR%"=="0" (
  echo *** Export failed ^(%ERR%^). Check Editor Settings ^> Export ^> Android: Java SDK path = %JAVA_HOME%, Android SDK path = %ANDROID_HOME%.
  exit /b %ERR%
)
echo.
echo Built "%ROOT%game\build\PMDRed-Thor.apk" (%MODE%) with ThorScreen.
echo Install:  "%ANDROID_HOME%\platform-tools\adb.exe" install -r "%ROOT%game\build\PMDRed.apk"
endlocal
