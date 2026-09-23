@echo off
chcp 65001 >nul
setlocal
title PalmDeck 开放防火墙（一次性）
echo ================================================
echo    PalmDeck · 放行防火墙端口
echo    （iPhone 连不上/一直“连接中”多半是这个原因）
echo ================================================
echo.

REM ---------- 提权（New-NetFirewallRule 需要管理员） ----------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 需要管理员权限，正在提权（点“是”）...
    powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo 正在添加放行规则...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue';" ^
  "New-NetFirewallRule -DisplayName 'PalmDeck TCP 8765' -Direction Inbound -Protocol TCP -LocalPort 8765 -Action Allow | Out-Null;" ^
  "New-NetFirewallRule -DisplayName 'PalmDeck TCP 8080' -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow | Out-Null;" ^
  "New-NetFirewallRule -DisplayName 'PalmDeck UDP 7773' -Direction Inbound -Protocol UDP -LocalPort 7773 -Action Allow | Out-Null;" ^
  "New-NetFirewallRule -DisplayName 'PalmDeck UDP 7774' -Direction Inbound -Protocol UDP -LocalPort 7774 -Action Allow | Out-Null;" ^
  "Write-Host '  已放行：TCP 8765 / 8080, UDP 7773 / 7774'"

echo.
echo 完成。现在重开 PalmDeck.exe，iPhone 再点“连接”即可。
echo （若仍连不上，把当前 Wi-Fi 设为“专用网络”：
echo   设置 - 网络和 Internet - Wi-Fi - 属性 - 网络配置文件类型 - 专用）
echo.
pause
