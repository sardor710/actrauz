@echo off
rem Builds the signed Play Store bundle. Needs android\key.properties (see key.properties.example) and env\dev.json.
set JAVA_HOME=D:\dev\jdk-17
set PATH=D:\lab\flutter\bin;%PATH%
cd /d "%~dp0.."
call flutter build appbundle --release --dart-define-from-file=env/dev.json
if errorlevel 1 exit /b 1
echo.
echo Bundle: %CD%\build\app\outputs\bundle\release\app-release.aab
