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
xcodebuild -project MG4Mate.xcodeproj -scheme MG4Mate \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build-device \
  CODE_SIGNING_ALLOWED=NO build | grep -E "error:|BUILD|\*\*" || true
