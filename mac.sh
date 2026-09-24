#!/bin/bash
# PalmDeck Mac 版：一键 编译 → 运行
# 用法：./mac.sh          （编译并运行）
#       ./mac.sh build    （只编译）
#       ./mac.sh clean    （清缓存后编译）

set -e
cd "$(dirname "$0")/mobile/ios/App"

APP=$(ls -d /Users/hui/Library/Developer/Xcode/DerivedData/App-*/Build/Products/Debug-maccatalyst/App.app 2>/dev/null | head -1)

case "${1:-run}" in
  clean)
    xcodebuild -project App.xcodeproj -scheme App -configuration Debug \
      -destination "platform=macOS,variant=Mac Catalyst" \
      -allowProvisioningUpdates clean build 2>&1 | grep -E "error:|BUILD" | head -20
    ;;
  build)
    xcodebuild -project App.xcodeproj -scheme App -configuration Debug \
      -destination "platform=macOS,variant=Mac Catalyst" \
      -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD" | head -20
    ;;
  run)
    xcodebuild -project App.xcodeproj -scheme App -configuration Debug \
      -destination "platform=macOS,variant=Mac Catalyst" \
      -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD" | head -20
    ;;
esac

APP=$(ls -d /Users/hui/Library/Developer/Xcode/DerivedData/App-*/Build/Products/Debug-maccatalyst/App.app 2>/dev/null | head -1)
if [ -n "$APP" ]; then
  pkill -f "Debug-maccatalyst/App.app" 2>/dev/null || true
  sleep 1
  open "$APP"
  echo "已启动：$APP"
else
  echo "没找到 Mac App，构建可能失败"
fi
