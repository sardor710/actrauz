@echo off
rem Runs the app in a browser on sample data, ignoring env\dev.json.
rem Port: first argument, else %PORT%, else 5599.
if not "%1"=="" set PORT=%1
if "%PORT%"=="" set PORT=5599
cd /d "%~dp0.."
flutter run -d web-server --web-port %PORT% --web-hostname localhost
