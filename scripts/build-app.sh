#!/bin/sh
# No accounts, signing certificates, package downloads, or Xcode project required.
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_HOME="${NCF_IMAGE_UPSCALER_HOME:-$HOME/Library/Application Support/ncf-image-upscaler}"
BUILD_DIR="$APP_HOME/runtime/native-build"
APP="$BUILD_DIR/NCF Image Upscaler.app"
PYTHON="${NCF_IMAGE_UPSCALER_PYTHON:-python3}"
case "${1:-}" in ''|--install) ;; *) printf '%s\n' 'Usage: scripts/build-app.sh [--install]' >&2; exit 2 ;; esac
if ! xcrun --find swiftc >/dev/null 2>&1; then
    printf '%s\n' 'Xcode Command Line Tools are required to build the app.' >&2
    exit 1
fi
mkdir -p "$BUILD_DIR/module-cache" "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos14.0 \
    -module-cache-path "$BUILD_DIR/module-cache" \
    "$PROJECT_DIR"/native/Sources/*.swift \
    -o "$APP/Contents/MacOS/NCFImageUpscaler"
"$PYTHON" - "$PROJECT_DIR/native/Info.plist" "$APP/Contents/Info.plist" "$APP_HOME" <<'PY'
import plistlib, sys
from pathlib import Path
source, destination, app_home = sys.argv[1:]
info = plistlib.loads(Path(source).read_bytes())
info['NCFImageUpscalerDataDirectory'] = str(Path(app_home).resolve())
Path(destination).write_bytes(plistlib.dumps(info))
PY
xcrun swift -module-cache-path "$BUILD_DIR/module-cache" \
    "$PROJECT_DIR/native/Tools/MakeIcon.swift" "$BUILD_DIR/AppIcon.iconset"
/usr/bin/iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/Licenses"
cp "$PROJECT_DIR/LICENSE" "$APP/Contents/Resources/Licenses/LICENSE"
cp "$PROJECT_DIR/THIRD_PARTY.md" "$APP/Contents/Resources/Licenses/THIRD_PARTY.md"
cp "$PROJECT_DIR"/licenses/*.txt "$APP/Contents/Resources/Licenses/"
/usr/bin/codesign --force --sign - "$APP"
if [ "${1:-}" = --install ]; then
    "$PYTHON" - "$APP" <<'PY'
import os, plistlib, shutil, sys, uuid
from pathlib import Path
source = Path(sys.argv[1])
directory = Path.home() / 'Applications'
directory.mkdir(exist_ok=True)
destination = directory / source.name
if destination.is_symlink():
    raise SystemExit(f'Existing symlink preserved: {destination}')
if destination.exists():
    try:
        old_info = plistlib.loads((destination / 'Contents/Info.plist').read_bytes())
    except (OSError, ValueError):
        raise SystemExit(f'Cannot replace an unrecognized app: {destination}')
    if old_info.get('CFBundleIdentifier') != 'local.ncf-image-upscaler.desktop':
        raise SystemExit(f'Existing app preserved: {destination}')
staging = directory / f'.ncf-image-upscaler-install-{uuid.uuid4()}.app'
backup = directory / f'.ncf-image-upscaler-backup-{uuid.uuid4()}.app'
try:
    shutil.copytree(source, staging)
    if destination.exists():
        destination.rename(backup)
    try:
        staging.rename(destination)
    except BaseException:
        if backup.exists():
            backup.rename(destination)
        raise
finally:
    shutil.rmtree(staging, ignore_errors=True)
    shutil.rmtree(backup, ignore_errors=True)
print(f'App installed: {destination}')
PY
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$HOME/Applications/NCF Image Upscaler.app"
else
    printf '%s\n' "$APP"
fi
