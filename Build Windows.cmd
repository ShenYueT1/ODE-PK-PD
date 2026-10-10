@echo off
setlocal
cd /d "%~dp0"
call flutter pub get
if errorlevel 1 goto failed
call flutter analyze
if errorlevel 1 goto failed
call flutter test
if errorlevel 1 goto failed
call flutter build windows --release
if errorlevel 1 goto failed
echo.
echo Build complete. Distribute the entire build\windows\x64\runner\Release folder.
pause
exit /b 0
:failed
echo.
echo Build stopped because a preceding step failed. See the output above.
pause
exit /b 1
