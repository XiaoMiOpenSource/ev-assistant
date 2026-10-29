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

echo "==> xcodebuild Release (generic/platform=iOS)"
# 只要 arm64 真机架构：CI runner 上模拟器运行时与 SDK 版本可能对不上，
# 带上模拟器切片会让资产编译阶段去找不存在的 runtime 而失败。
xcodebuild -project MG4Mate.xcodeproj -scheme MG4Mate \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build-device \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO EXCLUDED_ARCHS=x86_64 \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build-device/xcodebuild.log | grep -E "error:|BUILD|\*\*"
