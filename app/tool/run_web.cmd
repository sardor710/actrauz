@echo off
rem Runs the app in a browser. Port: %PORT% if set, otherwise 5599.
if "%PORT%"=="" set PORT=5599
cd /d "%~dp0.."
flutter run -d web-server --web-port %PORT% --web-hostname localhost
