@echo off
rem Builds the signed Play Store bundle. Needs android\key.properties (see key.properties.example) and env\dev.json.
set JAVA_HOME=D:\dev\jdk-17
set PATH=D:\lab\flutter\bin;%PATH%
cd /d "%~dp0.."
rem Without key.properties Gradle would sign with the debug key, and Play
rem rejects that bundle: stop before building.
if not exist "android\key.properties" (
  echo ERROR: %CD%\android\key.properties is missing. 1>&2
  echo A release bundle must be signed with the upload key, never the debug key. 1>&2
  echo Copy android\key.properties.example to android\key.properties and fill it in. 1>&2
  exit /b 1
)
call flutter build appbundle --release --dart-define-from-file=env/dev.json
if errorlevel 1 exit /b 1
echo.
echo Bundle: %CD%\build\app\outputs\bundle\release\app-release.aab
