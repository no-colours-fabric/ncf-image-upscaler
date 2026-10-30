#!/bin/sh
# Installs runtime artifacts outside the checkout and registers the user command.
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_HOME="${NCF_IMAGE_UPSCALER_HOME:-$HOME/Library/Application Support/ncf-image-upscaler}"
PYTHON="${NCF_IMAGE_UPSCALER_PYTHON:-python3}"
INCLUDE_APP=1
DEV=0
for option in "$@"; do
    case "$option" in
        --dev) DEV=1 ;;
        --cli-only) INCLUDE_APP=0 ;;
        *) printf '%s\n' 'Usage: scripts/install.sh [--dev] [--cli-only]' >&2; exit 2 ;;
    esac
done
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    printf '%s\n' 'macOS on Apple Silicon (M1 or later) is required.' >&2
    exit 1
fi
"$PYTHON" -c 'import sys; assert (3,12) <= sys.version_info < (3,15), "Python 3.12–3.14 is required"'
mkdir -p "$APP_HOME/runtime" "$APP_HOME/cache/uv" "$APP_HOME/models"
if [ ! -x "$APP_HOME/runtime/tooling/bin/uv" ]; then
    "$PYTHON" -m venv "$APP_HOME/runtime/tooling"
    "$APP_HOME/runtime/tooling/bin/python" -m pip install --disable-pip-version-check --no-cache-dir 'uv==0.13.4'
fi
export UV_PROJECT_ENVIRONMENT="$APP_HOME/runtime/env"
export UV_CACHE_DIR="$APP_HOME/cache/uv"
export UV_PYTHON_DOWNLOADS=never
if [ "$DEV" -eq 1 ]; then
    "$APP_HOME/runtime/tooling/bin/uv" sync --locked --python "$PYTHON" --project "$PROJECT_DIR"
else
    "$APP_HOME/runtime/tooling/bin/uv" sync --locked --no-dev --no-editable --python "$PYTHON" --project "$PROJECT_DIR"
fi
"$APP_HOME/runtime/env/bin/python" -m ncf_image_upscaler.installation "$PROJECT_DIR" --installed
if [ "$INCLUDE_APP" -eq 1 ]; then
    "$PROJECT_DIR/scripts/build-app.sh" --install
fi
printf '\n%s\n' 'Installation complete. Download models explicitly:'
printf '%s\n' '  ncf-upscale models download all'
