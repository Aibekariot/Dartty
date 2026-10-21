@echo off
rem Сборка Dartty: embed -> analyze -> compile exe -> patch -> build\Dartty.exe
setlocal
chcp 65001 >nul
cd /d "%~dp0"

call dart pub get || goto :fail
call dart run tool/embed_assets.dart || goto :fail
call dart analyze --fatal-infos || goto :fail
if not exist build mkdir build
call dart compile exe bin/dartty.dart -o build\Dartty.exe || goto :fail

rem Проверка exe до смены подсистемы: в консольном режиме виден код возврата.
build\Dartty.exe --selfcheck || goto :fail
call dart run tool/patch_subsystem.dart build\Dartty.exe || goto :fail

rem Иконка самого exe (необязательно): только если установлен rcedit.
set "RCEDIT="
for %%X in (rcedit.exe rcedit-x64.exe) do if not defined RCEDIT set "RCEDIT=%%~$PATH:X"
if not defined RCEDIT goto :done
copy /y build\Dartty.exe build\Dartty.noicon.exe >nul
"%RCEDIT%" build\Dartty.exe --set-icon assets\icons\app.ico
start "" /wait build\Dartty.exe --selfcheck
if errorlevel 1 (
  echo rcedit испортил exe, оставляю версию без иконки.
  move /y build\Dartty.noicon.exe build\Dartty.exe >nul
) else (
  del build\Dartty.noicon.exe
)

:done
echo.
echo Готово: build\Dartty.exe
exit /b 0

:fail
echo.
echo Сборка не удалась.
exit /b 1
