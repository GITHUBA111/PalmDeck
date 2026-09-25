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

## 二、云端打包（无需 Windows 机器）

工作流在 `.github/workflows/build-windows.yml`，已写好：

1. 打开仓库 → **Actions** 标签
2. 左侧选 **build-windows-exe** → 右侧 **Run workflow**（`workflow_dispatch` 已开启，直接点绿按钮）
3. 等十几分钟（要跑完整测试、打 exe、编译安装包，还会真装一遍再卸掉），
   运行完成 → 页面底部 **Artifacts** 下载 `PalmDeck-Windows`
4. 得到 **`PalmDeck-Setup-<版本>.exe`** —— 给玩家用的安装包（中文向导、开始菜单、
   卸载项、可选开机自启、WebView2 兜底）

> Artifacts **只传安装包这一个文件**：传两个 GitHub 会把上传物打成 zip（下载多一步解压），
> 而免安装单文件版 `PalmDeck.exe` 在 Release 里本就有裸的 —— 它真正的用途是
> 自动更新的直链（`updater.GITHUB_EXE`），不在 Artifacts。

> 打 tag（如 `v1.0`）推送也会自动触发同样打包，并自动创建 Release
> （**两个**裸文件都附上：`PalmDeck.exe` + `PalmDeck-Setup-<版本>.exe`）。
> **tag 必须等于 `updater.APP_VERSION`**（例如 APP_VERSION = `4.0.0` 就必须打 `v4.0.0`）。
> 自更新比的是「Release 的 tag」和「exe 里的 APP_VERSION」：tag 打成 `v0.3.3` 却装着
> 自报 `4.0.0` 的 exe，所有用户都会被判成「已是最新」——**静默地永远收不到更新**。
> 工作流里有一步会拦（`校验 tag 与 APP_VERSION 一致`），不一致直接失败，宁可不发版。
> **`PalmDeck.exe` 这个资产名不能改**：Windows 端的自动更新直链写死了它
> （`updater.py` 的 `GITHUB_EXE`）；安装包是**额外**给首次安装用的，不参与自动更新。
>
> 工作流里 `test` job 先跑（macos-latest：iOS 纯逻辑要 `swiftc`、启动页亮度要 `sips`，
> 只有 macOS 两样齐全），**测试红了不会出包**。
>
> `build` job 红了怎么查（很重要，踩过坑）：**别用 REST API**。
> job 日志要仓库 admin（返回 403）；匿名 REST API 额度 60/h、又和整个 NAT 出口共用，
> 一查就见底。所以**每次构建**都会把结果与诊断（`status=success/failure` +
> ISCC 输出、自检结果、冒烟日志尾巴）force-add 到 **`ci-diag` 分支**，本地用 git 拿：
>
> ```bash
> git fetch origin ci-diag && git show origin/ci-diag:.ci-diag.txt
> ```
>
> 另外失败步骤会发 `::error::` 注解（注解是公开可读的），但长久渠道是 `ci-diag`。

## 三、使用（目标电脑）

装一次 **vJoy**（飞行模拟用虚拟摇杆）+ **ViGEmBus**（开车/普通游戏用虚拟手柄），重启。

然后二选一：

- **安装包**：双击 `PalmDeck-Setup-<版本>.exe` →（SmartScreen 拦就「更多信息 → 仍要运行」）
  → 装到 `%LocalAppData%\Programs\PalmDeck`，免 UAC、中文向导。
  卸载在「设置 → 应用」里，会删掉自启项但保留 `%APPDATA%\PalmDeck`（布局不丢）。
- **免安装**：直接双击 `PalmDeck.exe`。

之后的步骤一样：
1. 右下角托盘出现 PalmDeck 图标，控制台独立窗口自动弹出
2. 手机同一 Wi-Fi，App 自动发现（Bonjour）或手动填 IP
3. 游戏里把 vJoy / Xbox 设备绑定一次

> 唯一绕不开的就是 vJoy/ViGEmBus 内核驱动，必须装一次 + 重启，无法内置进 exe。
> 装完缺什么，控制台「自检」页会逐条说清楚（也能直接开 `http://127.0.0.1:8080/api/doctor`）。

## 备注

- `preview/` 已删除：那 27 张截图拍的是 v3 时代的**手机网页座舱**，
  而 v4 把网页座舱整个删了（只留 Windows 驻留服务 + iOS App），
  留着会让人以为还能用手机浏览器当座舱。需要截图请从 v4 的 iOS App 重拍。
  历史版本可用 `git show <旧的 commit>:preview/current.png` 取回。
- 若不想传 iOS 源码，可只提交电脑侧文件（`bridge.py hotas.py palmdeck_config.py palmdeck_layouts.py updater.py web/ packaging/ .github/`），22 MB 里大部分是 `mobile/`。
