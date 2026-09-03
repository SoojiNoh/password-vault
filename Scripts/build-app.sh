#!/usr/bin/env bash
#
# 비밀번호 금고를 빌드해 PasswordVault.app 을 만듭니다.
#
#   ./Scripts/build-app.sh            # 인텔·애플실리콘 겸용(universal) 시도
#   ./Scripts/build-app.sh --native   # 이 맥의 CPU 용으로만 (빠름)
#
# Xcode 명령줄 도구만 있으면 되고 Xcode 앱 전체는 필요하지 않습니다.

set -euo pipefail

cd "$(dirname "$0")/.."
PACKAGE_ROOT="$(pwd)"

APP_NAME="PasswordVault"
DISPLAY_NAME="비밀번호 금고"
BUNDLE_ID="com.github.soojinoh.passwordvault"
VERSION="1.0.0"
BUILD="${GITHUB_RUN_NUMBER:-1}"
MIN_MACOS="13.0"

BUILD_DIR="$PACKAGE_ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

UNIVERSAL=1
if [[ "${1:-}" == "--native" ]]; then
  UNIVERSAL=0
fi

# 제한 시간을 두고 명령을 실행합니다. (macOS 에는 GNU timeout 이 없습니다.)
# 아이콘 그리기처럼 없어도 되는 단계가 화면 서버를 기다리며 멈춰 서서
# 빌드 전체를 붙잡는 일이 없게 하기 위한 것입니다.
run_with_timeout() {
  local limit="$1"
  shift
  "$@" &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [[ "$waited" -ge "$limit" ]]; then
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

# universal 여부에 따라 --arch 를 붙여 swift build 를 부릅니다.
# (빈 배열을 펼치면 오래된 bash 에서 터지므로 배열 대신 함수로 갈라 둡니다.)
run_swift_build() {
  if [[ "$UNIVERSAL" == "1" ]]; then
    swift build -c release --arch arm64 --arch x86_64 "$@"
  else
    swift build -c release "$@"
  fi
}

echo "==> 스위프트 패키지 빌드"
if [[ "$UNIVERSAL" == "1" ]]; then
  if ! run_swift_build; then
    echo "    universal 빌드에 실패했습니다. 이 맥의 CPU 용으로만 다시 시도합니다."
    UNIVERSAL=0
  fi
fi
run_swift_build

BIN_PATH="$(run_swift_build --show-bin-path)"
EXECUTABLE="$BIN_PATH/$APP_NAME"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "실행 파일을 찾지 못했습니다: $EXECUTABLE" >&2
  exit 1
fi

echo "==> 앱 번들 조립"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ko</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>이 맥 안에서만 동작합니다. 자료를 밖으로 보내지 않습니다.</string>
</dict>
</plist>
PLIST

echo "==> 아이콘 만들기"
ICON_WORK="$BUILD_DIR/icon"
ICONSET="$ICON_WORK/AppIcon.iconset"
rm -rf "$ICON_WORK"
mkdir -p "$ICONSET"

if run_with_timeout 90 swift "$PACKAGE_ROOT/Scripts/make-icon.swift" "$ICON_WORK/icon-1024.png"; then
  # iconutil 이 받아 주는 이름은 16/32/128/256/512 와 그 @2x 뿐입니다.
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_WORK/icon-1024.png" \
      --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON_WORK/icon-1024.png" \
      --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done

  if iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"; then
    echo "    아이콘을 넣었습니다."
  else
    echo "    iconutil 이 실패해 기본 아이콘을 씁니다."
  fi
else
  echo "    아이콘 생성을 건너뜁니다(기본 아이콘 사용)."
fi

echo "==> 임시 서명"
# 개발자 계정이 없어도 임시(ad-hoc) 서명은 됩니다.
# 서명이 아예 없으면 macOS 가 "손상되었다" 며 실행을 막는 경우가 있습니다.
if ! codesign --force --sign - --timestamp=none "$APP_BUNDLE"; then
  echo "    서명에 실패했습니다. 실행은 되지만 첫 실행 경고가 더 뜰 수 있습니다."
fi

echo "==> 자체 검사"
"$APP_BUNDLE/Contents/MacOS/$APP_NAME" --selftest

echo
echo "완성: $APP_BUNDLE"
echo "실행: open \"$APP_BUNDLE\""
