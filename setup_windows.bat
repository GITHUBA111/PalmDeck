@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
title PalmDeck 一键安装（Windows）
echo ================================================
echo    PalmDeck 电脑端 · 一键安装
echo    （装依赖 + 检查虚拟手柄驱动 + 启动）
echo ================================================
echo.

REM ---------- 1. 检查 Python ----------
where python >nul 2>nul
if errorlevel 1 (
    echo [1/4] 没找到 Python，正在打开下载页...
    echo       安装时务必勾选 "Add Python to PATH"
    start https://www.python.org/downloads/
    echo       装好后重新双击本文件。
    pause
    exit /b 1
)
echo [1/4] Python 已找到：
python --version
echo.

REM ---------- 2. 安装依赖 ----------
echo [2/4] 安装依赖（vgamepad / pyvjoy / zeroconf / qrcode / pystray / Pillow）...
python -m pip install --quiet --upgrade pip >nul 2>nul
python -m pip install --quiet pyvjoy zeroconf qrcode pystray Pillow
echo       完成
echo.

REM ---------- 3. 检查虚拟手柄驱动 ----------
echo [3/4] 检查虚拟手柄驱动...
set NEED_DRIVER=0
sc query vjoy >nul 2>nul
if errorlevel 1 (
    echo   [x] 未检测到 vJoy（飞行模拟用：虚拟摇杆，7 轴 + 16 键）
    echo       打开下载页，下载 vJoySetup.exe 安装：
    start https://github.com/jshafer817/vJoy/releases/latest
    set NEED_DRIVER=1
) else (
    echo   [OK] vJoy 已安装
)
sc query ViGEmBus >nul 2>nul
if errorlevel 1 (
    echo   [x] 未检测到 ViGEmBus（开车/普通游戏用：虚拟 Xbox 手柄）
    echo       打开下载页，下载 ViGEmBus_Setup_x64.exe 安装：
    start https://github.com/nefarius/ViGEmBus/releases/latest
    set NEED_DRIVER=1
) else (
    echo   [OK] ViGEmBus 已安装
)
echo.
if "%NEED_DRIVER%"=="1" (
    echo   *** 装完驱动后请重启电脑一次 ***
    echo      重启后再次双击本文件即可直接进入。
    echo.
    pause
    exit /b 0
)

REM ---------- 4. 启动 ----------
echo [4/4] 启动 PalmDeck 桥接...
echo.
timeout /t 2 /nobreak >nul
python start.py
pause
