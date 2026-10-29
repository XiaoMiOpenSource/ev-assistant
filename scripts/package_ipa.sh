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

# App Group 以「构建产物里的 Info.plist」为唯一来源：
# Swift 代码和 entitlements 用同一份值，测试包的 .test group 才不会一半生效一半不生效。
APP_GROUP=$(/usr/libexec/PlistBuddy -c "Print MG4AppGroup" "$APP/Info.plist" 2>/dev/null || true)
WIDGET_GROUP=$(/usr/libexec/PlistBuddy -c "Print MG4WidgetGroup" "$APP/Info.plist" 2>/dev/null || true)
case "$APP_GROUP" in ""|*'$('*) APP_GROUP="group.com.evstats.EVLogger" ;; esac
case "$WIDGET_GROUP" in ""|*'$('*) WIDGET_GROUP="group.mg4widget" ;; esac
echo "==> App Group：$APP_GROUP / $WIDGET_GROUP"

rm -rf dist
mkdir -p dist/Payload build-device/entitlements
ditto "$APP" "dist/Payload/MG4Mate.app"

echo "==> 生成 entitlements（先扩展后主程序）"
# 仓库里的 entitlements 写的是正式版 group 名，这里按本次构建的值替换一份临时文件
sed -e "s|group\.com\.evstats\.EVLogger|${APP_GROUP}|g" \
    -e "s|group\.mg4widget|${WIDGET_GROUP}|g" \
    Resources/Widget/MG4MateWidget.entitlements > build-device/entitlements/widget.plist
sed -e "s|group\.com\.evstats\.EVLogger|${APP_GROUP}|g" \
    -e "s|group\.mg4widget|${WIDGET_GROUP}|g" \
    Resources/MG4Mate.entitlements > build-device/entitlements/main.plist

codesign -f -s - --timestamp=none \
  --entitlements build-device/entitlements/widget.plist \
  "dist/Payload/MG4Mate.app/PlugIns/MG4MateWidget.appex"
codesign -f -s - --timestamp=none \
  --entitlements build-device/entitlements/main.plist \
  "dist/Payload/MG4Mate.app"

echo "==> 校验"
codesign -dv --entitlements :- "dist/Payload/MG4Mate.app" 2>&1 | grep -E "Identifier|Signature|application-groups" -A2 | head -8
# 签名的 entitlements 必须真的带上这两个 group，否则 App Group 会静默失效（配置存不住）
codesign -d --entitlements :- "dist/Payload/MG4Mate.app" 2>&1 | grep -q "$APP_GROUP" || {
  echo "❌ 主程序 entitlements 里没有 $APP_GROUP"; exit 1; }
codesign -d --entitlements :- "dist/Payload/MG4Mate.app/PlugIns/MG4MateWidget.appex" 2>&1 | grep -q "$WIDGET_GROUP" || {
  echo "❌ 小组件 entitlements 里没有 $WIDGET_GROUP"; exit 1; }
echo "✅ entitlements 里的 App Group 与 Info.plist 一致"

IPA="dist/EVHelper_v${VERSION}${NAME_SUFFIX}.tipa"
(cd dist && zip -qry "$(basename "$IPA")" Payload)
cp "$IPA" "dist/EVHelper_v${VERSION}${NAME_SUFFIX}.ipa"
rm -rf dist/Payload

echo ""
echo "✅ 产出：$IPA  （另存一份 .ipa，供普通签名工具使用）"
ls -lh dist/*.tipa dist/*.ipa | awk '{print "   ", $9, $5}'
shasum -a 256 "$IPA"
