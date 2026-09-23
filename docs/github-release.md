# 发布到 GitHub + 云端打包 Windows exe

整个项目只有约 22 MB，直接整个推上去即可（GitHub 单文件 100MB / 仓库 5GB 上限，远够用）。

## 一、推仓库（一次性）

1. 到 https://github.com/new 建一个空仓库（**不要**勾选 README/.gitignore，保持空）
2. 本机项目根目录执行：

```bash
git init
git add -A
git commit -m "PalmDeck"
git branch -M main
git remote add origin https://github.com/<你的用户名>/PalmDeck.git
git push -u origin main
```

> 已经写好了 `.gitignore`，`node_modules` / `Pods` / `.DS_Store` / 打包中间产物都不会被传上去。

## 二、云端打包 exe（无需 Windows 机器）

工作流在 `.github/workflows/build-windows.yml`，已写好：

1. 打开仓库 → **Actions** 标签
2. 左侧选 **build-windows-exe** → 右侧 **Run workflow**（`workflow_dispatch` 已开启，直接点绿按钮）
3. 等 1–2 分钟，运行完成 → 页面底部 **Artifacts** 下载 `PalmDeck-Windows-exe`
4. 解压得到 **`PalmDeck.exe`**（已内置 Python + 全部依赖，目标电脑免装 Python）

> 打 tag（如 `v1.0`）推送也会自动触发同样打包。

## 三、exe 使用（目标电脑）

1. 装一次 **vJoy**（飞行模拟用虚拟摇杆）+ **ViGEmBus**（开车/普通游戏用虚拟手柄），重启
2. 双击 `PalmDeck.exe`
3. 手机同一 Wi-Fi，App 自动发现（Bonjour）或手动填 IP
4. 游戏里把 vJoy 设备绑定一次

> 唯一绕不开的就是 vJoy/ViGEmBus 内核驱动，必须装一次 + 重启，无法内置进 exe。

## 备注

- `preview/` 里是设计截图（约 1.7 MB），会一并上传，不影响。
- 若不想传 iOS 源码，可只提交电脑侧文件（`bridge.py hotas.py telemetry.py palmdeck_config.py web/ packaging/ .github/`），22 MB 里大部分是 `mobile/`。
