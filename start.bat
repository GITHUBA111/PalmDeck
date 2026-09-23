@echo off
chcp 65001 >nul
cd /d "%~dp0"
title PalmDeck
python start.py
if errorlevel 1 python3 start.py
if errorlevel 1 (
  echo.
  echo 没找到 Python，请先安装 https://www.python.org/downloads/
  echo 安装时务必勾选 "Add Python to PATH"
  pause
)
