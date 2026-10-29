#!/bin/bash
# 构建 Release 真机二进制（不签名，交给 package_ipa.sh 注入权限）
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> xcodegen generate"
# 优先用 PATH 里的 xcodegen（brew install xcodegen），找不到再用仓库旁的便携版
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
elif [ -x ../bin/xcodegen/bin/xcodegen ]; then
  ../bin/xcodegen/bin/xcodegen generate >/dev/null
else
  echo "缺少 xcodegen：brew install xcodegen"; exit 1
fi

mkdir -p build-device

# 可选：把高德 Key 注入 Info.plist 的 AmapKey（值写的是 $(AMAP_KEY)）。
# 走临时 xcconfig + XCODE_XCCONFIG_FILE，而不是命令行参数 —— 因为 xcodebuild 会把命令行
# 原样打进 "Command line invocation" 日志，公网仓库的 AR 日志里就会漏 Key。
# 不设置 AMAP_KEY 时什么都不做：Info.plist 保留占位符，代码会当作「没有 Key」，
# 于是公开构建默认完全不请求第三方，用户可在 App 设置里手动填。
if [ -n "${AMAP_KEY:-}" ]; then
  printf 'AMAP_KEY = %s\n' "$AMAP_KEY" > build-device/amap.xcconfig
  export XCODE_XCCONFIG_FILE="$PWD/build-device/amap.xcconfig"
  echo "==> 已注入高德 Key（长度 ${#AMAP_KEY}，内容不打印）"
else
  echo "==> 未注入高德 Key（AMAP_KEY 为空），Info.plist 保留占位符"
fi

# 可选：测试包。TEST_BUILD=1 时包名加 .test 后缀、桌面名加「·测试」，
# 这样能和正式版并存在同一台手机上：iOS 按 bundle id 分配容器，
# 测试版的充电记录/凭证都在自己的容器里，不会写坏正式版。
# App Group 也一并换成 .test 后缀：测试版的车况配置与小组件快照各存一份，
# 不会覆盖正式版看到的数据；代价是测试版第一次打开要重新填一次接口地址。
if [ "${TEST_BUILD:-0}" = "1" ]; then
  export BUNDLE_ID_SUFFIX=".test"
  export APP_DISPLAY_NAME="电车助手·测试"
  export MG4_APP_GROUP="${MG4_APP_GROUP:-group.com.evstats.EVLogger.test}"
  export MG4_WIDGET_GROUP="${MG4_WIDGET_GROUP:-group.mg4widget.test}"
fi
BUNDLE_ID_SUFFIX="${BUNDLE_ID_SUFFIX:-}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-电车助手}"
MG4_APP_GROUP="${MG4_APP_GROUP:-group.com.evstats.EVLogger}"
MG4_WIDGET_GROUP="${MG4_WIDGET_GROUP:-group.mg4widget}"
echo "==> 包名后缀「${BUNDLE_ID_SUFFIX}」，显示名「${APP_DISPLAY_NAME}」"
echo "==> App Group「${MG4_APP_GROUP}」/「${MG4_WIDGET_GROUP}」"

echo "==> xcodebuild Release (generic/platform=iOS)"
# 只要 arm64 真机架构：CI runner 上模拟器运行时与 SDK 版本可能对不上，
# 带上模拟器切片会让资产编译阶段去找不存在的 runtime 而失败。
xcodebuild -project MG4Mate.xcodeproj -scheme MG4Mate \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build-device \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO EXCLUDED_ARCHS=x86_64 \
  BUNDLE_ID_SUFFIX="$BUNDLE_ID_SUFFIX" APP_DISPLAY_NAME="$APP_DISPLAY_NAME" \
  MG4_APP_GROUP="$MG4_APP_GROUP" MG4_WIDGET_GROUP="$MG4_WIDGET_GROUP" \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build-device/xcodebuild.log | grep -E "error:|BUILD|\*\*"
