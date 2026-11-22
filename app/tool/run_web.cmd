@echo off
rem Runs the app in a browser. Port: %PORT% if set, otherwise 5599.
rem With app\env\dev.json present (written by supabase\scripts\deploy.mjs) the
rem app talks to the Supabase project; without it, it runs on sample data.
if "%PORT%"=="" set PORT=5599
cd /d "%~dp0.."
set DEFINES=
if exist env\dev.json set DEFINES=--dart-define-from-file=env/dev.json
flutter run -d web-server --web-port %PORT% --web-hostname localhost %DEFINES%
