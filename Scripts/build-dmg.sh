#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
VERSION="${VERSION:-1.0.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
BUILD_ROOT="${PROJECT_ROOT}/build"
DERIVED_DATA="${BUILD_ROOT}/DerivedData"
DIST_DIR="${PROJECT_ROOT}/dist"
DMG_ROOT="${BUILD_ROOT}/dmg-root"
APP_PATH="${DERIVED_DATA}/Build/Products/Release/SimpleMenuNote.app"
DMG_PATH="${DIST_DIR}/SimpleMenuNote-${VERSION}.dmg"

mkdir -p "${BUILD_ROOT}" "${DIST_DIR}"

xcodebuild \
  -project "${PROJECT_ROOT}/SimpleMenuNote.xcodeproj" \
  -scheme SimpleMenuNote \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ -n "${SIGN_IDENTITY}" ]]; then
  codesign --force --deep \
    --options runtime \
    --timestamp \
    --sign "${SIGN_IDENTITY}" \
    --entitlements "${PROJECT_ROOT}/SimpleMenuNote/Resources/SimpleMenuNote.entitlements" \
    "${APP_PATH}"
else
  codesign --force --deep --sign - \
    --entitlements "${PROJECT_ROOT}/SimpleMenuNote/Resources/SimpleMenuNote.entitlements" \
    "${APP_PATH}"
fi

rm -rf "${DMG_ROOT}"
mkdir -p "${DMG_ROOT}"
ditto "${APP_PATH}" "${DMG_ROOT}/SimpleMenuNote.app"
ln -s /Applications "${DMG_ROOT}/Applications"
rm -f "${DMG_PATH}"
hdiutil create \
  -volname SimpleMenuNote \
  -srcfolder "${DMG_ROOT}" \
  -format UDZO \
  -ov \
  "${DMG_PATH}"

if [[ -n "${SIGN_IDENTITY}" ]]; then
  codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG_PATH}"
fi

echo "Created ${DMG_PATH}"
lipo -archs "${APP_PATH}/Contents/MacOS/SimpleMenuNote"
