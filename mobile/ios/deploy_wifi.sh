#!/usr/bin/env bash
# PalmDeck · 无线部署到 iPhone（同一 Wi-Fi，无需数据线）
#
# 前提（一次性）：Mac 与 iPhone 已配对、iPhone 已开「开发者模式」；
#                之后只要二者在同一局域网即可纯 Wi-Fi 部署。
#
# 用法：
#   ./deploy_wifi.sh                  # 自动选第一台已配对真机
#   ./deploy_wifi.sh hui              # 指定设备名
#   ./deploy_wifi.sh --launch hui     # 装完顺便启动
#   ./deploy_wifi.sh --wifi-only hui  # 若检测到 USB 上有 iPhone 就拒绝（强制走网络）
#
# 也可用环境变量： LAUNCH=1  WIFI_ONLY=1
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"          # mobile/ios
APP_DIR="$HERE/App"
SCHEME="${SCHEME:-App}"
BUNDLE_ID="${BUNDLE_ID:-com.palmdeck.yoke}"
DD="$HERE/.deploy-dd"                          # 固定 DerivedData，便于定位产物

WANT=""
WIFI_ONLY="${WIFI_ONLY:-0}"
LAUNCH="${LAUNCH:-0}"

usage() {
  cat <<'EOS'
PalmDeck · 无线部署到 iPhone（同一 Wi-Fi，无需数据线）

前提（一次性）：Mac 与 iPhone 已配对、iPhone 已开「开发者模式」；
                之后只要二者在同一局域网即可纯 Wi-Fi 部署。

用法：
  ./deploy_wifi.sh                  # 自动选第一台已配对真机
  ./deploy_wifi.sh hui              # 指定设备名
  ./deploy_wifi.sh --launch hui     # 装完顺便启动
  ./deploy_wifi.sh --wifi-only hui  # 检测到 USB 上有 iPhone 就拒绝（强制走网络）

环境变量： LAUNCH=1  WIFI_ONLY=1  SCHEME=App  BUNDLE_ID=com.palmdeck.yoke
EOS
}

for arg in "$@"; do
  case "$arg" in
    --wifi-only) WIFI_ONLY=1 ;;
    --launch)    LAUNCH=1 ;;
    -h|--help)   usage; exit 0 ;;
    -*)          echo "未知参数：$arg（-h 看用法）"; exit 2 ;;
    *)           WANT="$arg" ;;
  esac
done

# ---------- 小工具 ----------
MAC_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"

iphone_on_usb() {
  system_profiler SPUSBDataType 2>/dev/null | grep -qiE "iPhone|iPad"
}

hints() {
  cat <<EOS

── 排查建议 ─────────────────────────────────────────
  1) 同一 Wi-Fi：iPhone 与 Mac 必须连同一个网络
     （Mac 当前局域网 IP：${MAC_IP:-未获取到}）
  2) iPhone 解锁并亮屏：锁屏久了 iOS 会切断开发通道
  3) 开发者模式：设置 → 隐私与安全性 → 开发者模式（需重启一次）
  4) 从未配对过：先用数据线连一次，Xcode → Window → Devices and Simulators 里配对
  5) 刚重启/换网：等 5~10 秒再跑一次
  查看当前设备：  xcrun devicectl list devices
─────────────────────────────────────────────────────
EOS
}

die() { echo "!! $*"; hints; exit 1; }

# ---------- 0. 网络与 USB 体检 ----------
echo "==> 网络：Mac 局域网 IP = ${MAC_IP:-未获取到}"
if [ -z "$MAC_IP" ]; then
  echo "    警告：没拿到局域网 IP，Mac 可能没连 Wi-Fi（仍可尝试，但多半失败）"
fi

if [ "$WIFI_ONLY" = "1" ] && iphone_on_usb; then
  die "--wifi-only：检测到 iPhone 插在 USB 上。请拔掉数据线后重试，以确保走 Wi-Fi。"
fi

# ---------- 1. 找真机 ----------
LABEL=""; [ -n "$WANT" ] && LABEL="（名称=${WANT}）"
echo "==> 查找已配对真机$LABEL"
DEVS_JSON="$(mktemp)"
xcrun devicectl list devices --json-output "$DEVS_JSON" >/dev/null 2>&1 || true

UDID="$(python3 - "$DEVS_JSON" "$WANT" <<'PY'
import json, sys
path, want = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
try:
    data = json.load(open(path))
except Exception:
    print(""); raise SystemExit
for dev in data.get("result", {}).get("devices", []):
    props = dev.get("properties", {}) or {}
    hp = props.get("hardwareProperties") or dev.get("hardwareProperties", {})
    dp = props.get("deviceProperties") or dev.get("deviceProperties", {})
    conn = props.get("connectionProperties") or dev.get("connectionProperties", {})
    if hp.get("reality") != "physical":
        continue
    if conn.get("pairingState") not in (None, "paired"):
        continue
    if want and dp.get("name") != want:
        continue
    print(hp.get("udid") or "")
    break
PY
)"
rm -f "$DEVS_JSON"

[ -n "${UDID:-}" ] || die "没有找到已配对真机${LABEL}。"
echo "    设备 UDID = $UDID"

# ---------- 2. 编译 ----------
echo "==> 编译（真机 Debug，自动签名）"
cd "$APP_DIR"
if ! xcodebuild -workspace App.xcworkspace -scheme "$SCHEME" -configuration Debug \
      -destination "id=$UDID" -derivedDataPath "$DD" \
      -allowProvisioningUpdates build; then
  echo "!! 编译失败（这是代码/签名问题，不是 Wi-Fi 问题）。请查看上方 error: 行。"
  exit 1
fi

APP="$DD/Build/Products/Debug-iphoneos/$SCHEME.app"
[ -d "$APP" ] || die "未找到产物：$APP"

# ---------- 3. 无线安装（失败自动重试一次） ----------
echo "==> 无线安装到 iPhone"
if ! xcrun devicectl device install app --device "$UDID" -t 60 "$APP"; then
  echo "    首次失败，5 秒后重试一次（iOS 有时需要唤醒开发通道）…"
  sleep 5
  xcrun devicectl device install app --device "$UDID" -t 60 "$APP" \
    || die "安装失败。请解锁 iPhone 并确认在同一 Wi-Fi 后重试。"
fi

# ---------- 4. 可选启动 ----------
if [ "$LAUNCH" = "1" ]; then
  echo "==> 启动 $BUNDLE_ID"
  xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" || true
fi

echo "==> 完成 ✅  （Wi-Fi 直推，无需数据线）"
