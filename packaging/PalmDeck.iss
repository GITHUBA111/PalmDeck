; PalmDeck · Windows 安装包（Inno Setup 6）
;
; 编译（需要先有 dist\PalmDeck.exe，即先跑 pyinstaller）：
;   packaging\build_installer.bat
; 或在 CI / 手工指定版本：
;   ISCC /dAppVersion=4.0.0 packaging\PalmDeck.iss
;
; 产物：dist\PalmDeck-Setup-<版本>.exe
;
; ── 三条不能随手改的约定（都有测试盯着，见 tests/test_installer.py）──
; ① 装到 {localappdata}（用户目录），PrivilegesRequired=lowest：
;    全程不弹 UAC；更重要的是**安装目录可写** —— updater.apply_update() 是
;    把新 exe 下载到 exe 旁边再自替换，装进 Program Files 会让自动更新静默失效。
; ② 自启项的名字/位置必须与 start.py 的 _AUTOSTART_KEY / _AUTOSTART_NAME 逐字一致
;    （托盘里那个「开机自启」开关和安装时的勾选框是同一个开关，不能打架）。
; ③ 卸载要删掉那个自启项（uninsdeletevalue）—— 否则删了程序会留一个指向空气的
;    自启项，开机报错。%APPDATA%\PalmDeck（日志/配置/布局）默认保留：重装不该丢布局。

#ifndef AppVersion
  ; 不传版本号就直接报错，免得打出一个叫 PalmDeck-Setup-0.0.0.exe 的东西发出去
  #error 需要 /dAppVersion=x.y.z —— 用 packaging\build_installer.bat，或见本文件顶部
#endif

#define AppName "PalmDeck"
#define AppExe "PalmDeck.exe"
#define AppPublisher "PalmDeck"

[Setup]
AppId={{8E1B7C2A-5D3F-4A9E-9C41-2F0B6D5A7E10}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\PalmDeck
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; 用户目录安装：不弹 UAC，且目录可写 ⇒ 原地自替换（自动更新）继续有效。
; 刻意**不**写 PrivilegesRequiredOverridesAllowed=dialog：那会给向导加一个
; 「为所有用户安装？/ 只为我自己安装？」的选择页，选了前者就要 UAC ——
; 与「免 UAC」这个目标正好相反，而且对一个装在用户目录的守护程序毫无意义。
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=PalmDeck-Setup-{#AppVersion}
SetupIconFile=..\packaging\PalmDeck.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName} {#AppVersion}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
; 覆盖安装 / 卸载时用 Restart Manager 请托盘进程退出（否则文件占用会失败）
CloseApplications=yes
RestartApplications=no
ArchitecturesInstallIn64BitMode=x64compatible
; 只装到跑得起来的系统上：exe 是 Python 3.12 + PyInstaller 打的，本来也跑不了 Win7/8。
; 与其装完一启动就崩（报错还是 exe 吐的，玩家看不懂），不如在这里就拦住。
ArchitecturesAllowed=x64compatible
MinVersion=10.0

[Languages]
; 中文向导。该文件来自 Inno Setup 官方“非官方翻译”列表（见文件头部署名，MIT）：
;   https://github.com/kira-96/Inno-Setup-Chinese-Simplified-Translation
; 它要求 **Inno Setup 6.5+**（CI 的 windows-latest 自带 6.7.1）。
; 为什么入库而不是让 CI 去下：下载失败 = 发版被网络拖累；而且一个纯文本翻译
; 跟着仓库走才能在评审里看到它变没变。（同样原因，.ico 也是入库的。）
Name: "chinese"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked
Name: "autostart"; Description: "开机自动启动（可随时在托盘菜单里关）"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
Source: "..\dist\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion

; ── O3-full 真窗口的 Runtime 兜底（见 docs/PalmDeck-v4-native-window.md）──
; 没有 WebView2 Runtime 时，真窗口会退回 O3-lite（浏览器应用窗口）—— 功能不丢。
; 打包时若 packaging\ 里放了 MicrosoftEdgeWebview2Setup.exe（CI 会下），就带进去、
; 缺失时静默装；没放就 #if 跳过 —— 安装包照常能编、能用。
#if FileExists(AddBackslash(SourcePath) + "MicrosoftEdgeWebview2Setup.exe")
Source: "MicrosoftEdgeWebview2Setup.exe"; DestDir: "{tmp}"; \
    Flags: deleteafterinstall; Check: WebView2Missing
#endif

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; 与 start.py 的 _AUTOSTART_KEY / _AUTOSTART_NAME 一致；uninsdeletevalue = 卸载时删掉
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; \
    ValueType: string; ValueName: "{#AppName}"; ValueData: """{app}\{#AppExe}"""; \
    Flags: uninsdeletevalue; Tasks: autostart

[Run]
; 缺 WebView2 时先装 Runtime（装了才会出真窗口），再启动程序。只用用户权限，不弹 UAC。
#if FileExists(AddBackslash(SourcePath) + "MicrosoftEdgeWebview2Setup.exe")
Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; \
    StatusMsg: "正在安装 WebView2 运行时…"; Flags: waituntilterminated; Check: WebView2Missing
#endif
Filename: "{app}\{#AppExe}"; Description: "立即启动 {#AppName}"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 只清程序自己装的目录；%APPDATA%\PalmDeck（日志 / 配置 / 布局）特意不动
Type: filesandordirs; Name: "{app}"

[Code]
// 注意：[Code] 是 Pascal Script —— 注释只能用 // 或 { }，用 ; 会被当成语句、编译直接失败。
// WebView2 Runtime 的 EdgeUpdate client GUID —— 与 palmdeck_window._WEBVIEW2_CLIENT 逐字相同
// （tests/test_window.py 会对账）。查不到就当「没装」：宁可多装一次 Runtime，
// 也不要拿一个缺渲染引擎的真窗口去唬玩家。
const
  WebView2Client = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';

function WebView2Installed(): Boolean;
var
  pv: String;
begin
  Result :=
    RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\' + WebView2Client, 'pv', pv) or
    RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\' + WebView2Client, 'pv', pv) or
    RegQueryStringValue(HKCU, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\' + WebView2Client, 'pv', pv);
  if Result then
    Result := (pv <> '') and (pv <> '0.0.0.0');
end;

function WebView2Missing(): Boolean;
begin
  Result := not WebView2Installed();
end;
