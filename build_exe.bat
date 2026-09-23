@echo off
chcp 65001 >nul
cd /d "%~dp0"
title PalmDeck 打包 exe
echo 正在安装 PyInstaller 与后端依赖...
python -m pip install --quiet pyinstaller vgamepad pyvjoy zeroconf qrcode
echo 打包中（几分钟，请勿关闭）...
python -m PyInstaller --clean --noconfirm packaging\PalmDeck.spec
echo.
if exist "dist\PalmDeck.exe" (
    echo 完成！单文件可执行程序：dist\PalmDeck.exe
    echo 把 dist\PalmDeck.exe 拷到任何 Windows 电脑双击即可（无需装 Python）
) else (
    echo 打包失败，请把上面红字截图反馈
)
pause
