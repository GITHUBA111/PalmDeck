@echo off
rem 在 Windows 上打安装包（Inno Setup 6，**需 6.5+** —— 中文向导文件的要求）。
rem
rem 前置：先出 exe —— pyinstaller packaging\PalmDeck.spec
rem 产物：..\dist\PalmDeck-Setup-<版本>.exe
rem
rem 版本号从 updater.APP_VERSION 读，不手抄 —— 与 exe 的文件属性同一个真相源。
setlocal
cd /d "%~dp0"

rem Inno Setup 装完**不会**把自己加进 PATH，所以别只靠 where —— 先看标准安装位置。
set "ISCC="
for %%p in ("%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" "%ProgramFiles%\Inno Setup 6\ISCC.exe") do (
    if not defined ISCC if exist %%p set "ISCC=%%~p"
)
if not defined ISCC (
    for /f "delims=" %%p in ('where ISCC 2^>nul') do if not defined ISCC set "ISCC=%%p"
)
if not defined ISCC (
    echo [x] 找不到 ISCC.exe —— 装 Inno Setup 6.5+ 后重试：https://jrsoftware.org/isdl.php
    echo     或用 choco install innosetup -y
    echo     装完还找不到就把它加进 PATH，或手工跑：
    echo     ISCC /dAppVersion=x.y.z PalmDeck.iss
    exit /b 1
)
echo [*] 用 %ISCC%

for /f "usebackq delims=" %%v in (`python -c "import sys; sys.path.insert(0, r'%~dp0..'); from updater import APP_VERSION; print(APP_VERSION)"`) do set "VER=%%v"
if "%VER%"=="" (
    echo [x] 取不到版本号（要能跑 python 且仓库完整）
    exit /b 1
)

if not exist "..\dist\PalmDeck.exe" (
    echo [x] 还没有 ..\dist\PalmDeck.exe —— 先跑：pyinstaller packaging\PalmDeck.spec
    exit /b 1
)

echo [*] 编译安装包，版本 %VER% …
"%ISCC%" /dAppVersion=%VER% PalmDeck.iss || exit /b 1

echo.
echo [√] 完成：%CD%\..\dist\PalmDeck-Setup-%VER%.exe
