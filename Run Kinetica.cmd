@echo off
setlocal
cd /d "%~dp0"
where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter was not found on PATH. Install Flutter and see README.md.
  pause
  exit /b 1
)
call flutter pub get
if errorlevel 1 goto failed
call flutter run -d windows --release
if errorlevel 1 goto failed
exit /b 0
:failed
echo.
echo Launch failed. Review the message above and run flutter doctor -v.
echo Windows builds require Visual Studio Desktop development with C++.
pause
exit /b 1
