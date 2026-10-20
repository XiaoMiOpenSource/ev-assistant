#!/bin/bash
# 构建 Release 真机二进制（不签名，交给 package_ipa.sh 注入权限）
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> xcodegen generate"
../bin/xcodegen/bin/xcodegen generate >/dev/null

echo "==> xcodebuild Release (generic/platform=iOS)"
xcodebuild -project MG4Mate.xcodeproj -scheme MG4Mate \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build-device \
  CODE_SIGNING_ALLOWED=NO build | grep -E "error:|BUILD|\*\*" || true
