@echo off
rem ============================================================================
rem  YouTube 3D Vision - one-command installer (Windows)
rem
rem  Downloads the add-on, unpacks it, gets a browser that can load it
rem  automatically, and opens YouTube with 3D already switched on.
rem
rem  Chrome removed the ability to auto-load an unpacked add-on in version 137
rem  (a security change), so this installs "Chrome for Testing" - the same
rem  browser, but it keeps that ability. Your normal Chrome is not touched.
rem
rem  Usage: double-click this file, or run it in a terminal.
rem ============================================================================
setlocal EnableDelayedExpansion
set "BASE=https://pj9811193-create.github.io/my-files"
set "DEST=%LOCALAPPDATA%\YouTube3DVision"
set "BUILD=9"
set "CFT_VERSION=154.0.8037.92"

if not exist "%DEST%" mkdir "%DEST%"
cd /d "%DEST%"

echo * Downloading the 3D add-on...
set "DL=%DEST%\.download"
if exist "%DL%" rmdir /s /q "%DL%"
mkdir "%DL%"
set "PARTS="
set /a i=0
:dl
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing -Uri '%BASE%/youtube-3d-vision.zip.part%i%?v=%BUILD%' -OutFile '%DL%\part%i%' } catch { exit 1 }" >nul 2>&1
if errorlevel 1 goto dl_done
set "PARTS=!PARTS!+"%DL%\part%i%""
set /a i+=1
goto dl
:dl_done
if %i%==0 (
  echo   Could not download the add-on. Check your internet connection.
  pause & exit /b 1
)
echo   got %i% pieces
rem join the pieces (the leading + is stripped by the copy command syntax)
set "PARTS=!PARTS:~1!"
copy /b !PARTS! "%DEST%\yt3d.zip" >nul
rmdir /s /q "%DL%"

echo * Unpacking...
if exist "%DEST%\youtube-3d-vision" rmdir /s /q "%DEST%\youtube-3d-vision"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Force -Path '%DEST%\yt3d.zip' -DestinationPath '%DEST%'"
if not exist "%DEST%\youtube-3d-vision\manifest.json" (
  echo   Unpacking failed.
  pause & exit /b 1
)
del "%DEST%\yt3d.zip" >nul 2>&1

set "BROWSER="
if exist "%DEST%\chrome-win64\chrome.exe" set "BROWSER=%DEST%\chrome-win64\chrome.exe"
if not defined BROWSER if exist "%LOCALAPPDATA%\Chromium\Application\chrome.exe" set "BROWSER=%LOCALAPPDATA%\Chromium\Application\chrome.exe"

if not defined BROWSER (
  echo * Fetching a browser that can load the 3D add-on ^(Chrome for Testing, ~150 MB, one time^)...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri 'https://storage.googleapis.com/chrome-for-testing-public/%CFT_VERSION%/win64/chrome-win64.zip' -OutFile '%DEST%\cft.zip'"
  if not exist "%DEST%\cft.zip" (
    echo   Could not download the browser.
    pause & exit /b 1
  )
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Force -Path '%DEST%\cft.zip' -DestinationPath '%DEST%'"
  del "%DEST%\cft.zip" >nul 2>&1
  set "BROWSER=%DEST%\chrome-win64\chrome.exe"
)
if not exist "%BROWSER%" (
  echo   No usable browser found.
  pause & exit /b 1
)

echo * Starting the browser with 3D built in...
rem Start the browser first, then open YouTube a few seconds later: the add-on
rem needs a moment to come up, and a page opened in that first instant would
rem not get it.
start "" "%BROWSER%" --load-extension="%DEST%\youtube-3d-vision" --user-data-dir="%DEST%\profile" --no-first-run --no-default-browser-check about:blank
timeout /t 5 /nobreak >nul
start "" "%BROWSER%" --load-extension="%DEST%\youtube-3d-vision" --user-data-dir="%DEST%\profile" "https://www.youtube.com"

echo.
echo Done. YouTube is opening now.
echo   - Open any normal video; the 3D switches itself on after a few seconds.
echo   - Put on red-cyan glasses (or pick Side-by-side for a 3D TV / headset).
echo   - Run it again later:  "%BROWSER%" --load-extension="%DEST%\youtube-3d-vision" --user-data-dir="%DEST%\profile"
echo   - Nothing was installed into your normal Chrome.
echo.
pause
