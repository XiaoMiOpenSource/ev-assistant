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

echo "==> xcodebuild Release (generic/platform=iOS)"
# 只要 arm64 真机架构：CI runner 上模拟器运行时与 SDK 版本可能对不上，
# 带上模拟器切片会让资产编译阶段去找不存在的 runtime 而失败。
mkdir -p build-device
xcodebuild -project MG4Mate.xcodeproj -scheme MG4Mate \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build-device \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO EXCLUDED_ARCHS=x86_64 \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build-device/xcodebuild.log | grep -E "error:|BUILD|\*\*"
