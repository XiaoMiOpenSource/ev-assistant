#!/bin/bash
# =====================================================================
# MG4 助手 · 未签名 → ad-hoc 注入 App Group 权限 → IPA / tIPA
# 与「车况」1.0.28 交付包同一套流程：TrollStore 可直接安装，
# 主程序与小组件扩展都带上 group.com.evstats.EVLogger + group.mg4widget。
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build-device/Build/Products/Release-iphoneos/MG4Mate.app"
[ -d "$APP" ] || { echo "请先运行 scripts/build_device.sh"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Info.plist")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
DISPLAY_NAME=$(/usr/libexec/PlistBuddy -c "Print CFBundleDisplayName" "$APP/Info.plist")
# 测试包（PACKAGE_SUFFIX=_test）另起文件名，避免和正式包混在一个目录里
NAME_SUFFIX="${PACKAGE_SUFFIX:-}"
echo "==> $DISPLAY_NAME  $BUNDLE_ID  $VERSION ($BUILD)"

rm -rf dist
mkdir -p dist/Payload
ditto "$APP" "dist/Payload/MG4Mate.app"

echo "==> 注入 entitlements（先扩展后主程序）"
codesign -f -s - --timestamp=none \
  --entitlements Resources/Widget/MG4MateWidget.entitlements \
  "dist/Payload/MG4Mate.app/PlugIns/MG4MateWidget.appex"
codesign -f -s - --timestamp=none \
  --entitlements Resources/MG4Mate.entitlements \
  "dist/Payload/MG4Mate.app"

echo "==> 校验"
codesign -dv --entitlements :- "dist/Payload/MG4Mate.app" 2>&1 | grep -E "Identifier|Signature|application-groups" -A2 | head -8

IPA="dist/EVHelper_v${VERSION}${NAME_SUFFIX}.tipa"
(cd dist && zip -qry "$(basename "$IPA")" Payload)
cp "$IPA" "dist/EVHelper_v${VERSION}${NAME_SUFFIX}.ipa"
rm -rf dist/Payload

echo ""
echo "✅ 产出：$IPA  （另存一份 .ipa，供普通签名工具使用）"
ls -lh dist/*.tipa dist/*.ipa | awk '{print "   ", $9, $5}'
shasum -a 256 "$IPA"
