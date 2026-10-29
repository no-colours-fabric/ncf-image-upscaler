#!/bin/sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_HOME="${IMAGE_UPSCALER_HOME:-$HOME/Library/Application Support/image-upscaler}"
BUILD_DIR="$APP_HOME/runtime/native-build/tests"
mkdir -p "$BUILD_DIR/module-cache"
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 \
    -module-cache-path "$BUILD_DIR/module-cache" \
    "$PROJECT_DIR/native/Sources/Support.swift" \
    "$PROJECT_DIR/native/Sources/PortableRuntime.swift" \
    "$PROJECT_DIR/native/Sources/ModelSetupController.swift" \
    "$PROJECT_DIR/native/Sources/FileOperations.swift" \
    "$PROJECT_DIR/native/Sources/ThumbnailLayout.swift" \
    "$PROJECT_DIR/native/Sources/ThumbnailCache.swift" \
    "$PROJECT_DIR/native/Sources/ComparisonView.swift" \
    "$PROJECT_DIR/native/Sources/FolderSession.swift" \
    "$PROJECT_DIR/native/Sources/FolderSidebar.swift" \
    "$PROJECT_DIR/native/Sources/ImageWindowController.swift" \
    "$PROJECT_DIR/native/Sources/WorkerTask.swift" \
    "$PROJECT_DIR/native/Tests/main.swift" -o "$BUILD_DIR/native-tests"
"$BUILD_DIR/native-tests"
