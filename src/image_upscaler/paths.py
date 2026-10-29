"""Application data lives outside the source checkout."""

import os
from pathlib import Path


def app_home() -> Path:
    override = os.environ.get("IMAGE_UPSCALER_HOME")
    if override:
        return Path(override).expanduser().resolve()
    return Path.home() / "Library" / "Application Support" / "image-upscaler"


def models_home() -> Path:
    return app_home() / "models"
