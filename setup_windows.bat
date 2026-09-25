@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
title PalmDeck 一键安装（Windows）
echo ================================================
echo    PalmDeck 电脑端 · 一键安装
echo    （装依赖 + 体检 + 启动）
echo ================================================
echo.

REM ---------- 1. 检查 Python ----------
where python >nul 2>nul
if errorlevel 1 (
    echo [1/3] 没找到 Python，正在打开下载页...
    echo       安装时务必勾选 "Add to PATH"
    start https://www.python.org/downloads/
    echo       装好后重新双击本文件。
    pause
    exit /b 1
)
echo [1/3] Python 已找到：
python --version
echo.

REM ---------- 2. 安装依赖 ----------
echo [2/3] 安装依赖...
python -m pip install --quiet --upgrade pip >nul 2>nul
python -m pip install --quiet pyvjoy zeroconf qrcode pystray Pillow
echo       完成
echo.

REM ---------- 3. 环境自检（驱动 / 防火墙 / 端口）----------
REM 具体检查逻辑只有一处：palmdeck_doctor.py（控制台「自检」页也是它）。
echo [3/3] 环境自检...
echo.
python palmdeck_doctor.py
echo.
echo ----------------------------------------------------------------
echo  缺 vJoy / ViGEmBus 就点它给的链接装一个，装完**重启电脑**。
echo  之后所有体检都在网页控制台的「自检」页里做（不用再回来双击 bat）。
echo  防火墙没放行也在那里一键放行。
echo ----------------------------------------------------------------
echo.
pause
echo 正在启动 PalmDeck 服务...
timeout /t 1 /nobreak >nul
python start.py
pause
