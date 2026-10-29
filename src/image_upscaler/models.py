"""Pinned model artifacts. Only download_model() accesses the network."""

import hashlib
import json
import os
import tempfile
from dataclasses import dataclass
from importlib.resources import files
from pathlib import Path
from urllib.request import Request, urlopen

from . import __version__
from .paths import models_home


@dataclass(frozen=True)
class ModelSpec:
    id: str
    title: str
    repository: str
    revision: str
    sha256: str
    size: int
    architecture: str
    scale: int
    blocks: int
    license: str

    @property
    def url(self) -> str:
        return f"https://huggingface.co/{self.repository}/resolve/{self.revision}/model.safetensors"


def registry() -> dict[str, ModelSpec]:
    manifest = json.loads(files("image_upscaler").joinpath("models.json").read_text())
    return {key: ModelSpec(id=key, **value) for key, value in manifest.items()}


def model_path(spec: ModelSpec) -> Path:
    return models_home() / spec.id / spec.revision / "model.safetensors"


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def require_model(spec: ModelSpec) -> Path:
    """Fail closed: no fallback download, even if weights are missing/corrupt."""
    path = model_path(spec)
    if not path.is_file():
        raise FileNotFoundError(
            f"Model {spec.id} is not installed. Run: upscale models download {spec.id}"
        )
    if path.stat().st_size != spec.size or sha256(path) != spec.sha256:
        raise ValueError(
            f"Model {spec.id} is corrupted. Run again: upscale models download {spec.id}"
        )
    return path


def download_model(spec: ModelSpec) -> Path:
    destination = model_path(spec)
    if destination.is_file():
        try:
            return require_model(spec)
        except ValueError:
            pass
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".download-", dir=destination.parent)
    temporary = Path(name)
    try:
        request = Request(spec.url, headers={"User-Agent": f"image-upscaler/{__version__}"})
        with os.fdopen(fd, "wb") as target:
            with urlopen(request, timeout=60) as source:
                received = 0
                while chunk := source.read(1024 * 1024):
                    received += len(chunk)
                    if received > spec.size:
                        raise ValueError(f"Unexpected model size for {spec.id}")
                    target.write(chunk)
        if temporary.stat().st_size != spec.size or sha256(temporary) != spec.sha256:
            raise ValueError(f"Model checksum mismatch for {spec.id}")
        os.replace(temporary, destination)
        return destination
    finally:
        temporary.unlink(missing_ok=True)


def choose_model(preset: str, scale: int) -> ModelSpec:
    key = ("x2plus" if scale in (1, 2) else "x4plus") if preset == "photo" else preset
    return registry()[key]
