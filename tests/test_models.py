import hashlib
import io
from dataclasses import replace
from pathlib import Path

import pytest

from ncf_image_upscaler import models


def spec_for(data):
    return replace(
        next(iter(models.registry().values())),
        size=len(data),
        sha256=hashlib.sha256(data).hexdigest(),
    )


def test_missing_and_corrupt_models_never_trigger_network(tmp_path, monkeypatch):
    monkeypatch.setenv("NCF_IMAGE_UPSCALER_HOME", str(tmp_path))

    def forbidden(*args, **kwargs):
        pytest.fail("Offline model lookup attempted a network request")

    monkeypatch.setattr(models, "urlopen", forbidden)
    spec = spec_for(b"weights")
    with pytest.raises(FileNotFoundError):
        models.require_model(spec)
    destination = models.model_path(spec)
    destination.parent.mkdir(parents=True)
    destination.write_bytes(b"invalid")
    with pytest.raises(ValueError):
        models.require_model(spec)


def test_failed_download_never_publishes_bad_weights(tmp_path, monkeypatch):
    monkeypatch.setenv("NCF_IMAGE_UPSCALER_HOME", str(tmp_path))
    spec = spec_for(b"correct")
    monkeypatch.setattr(models, "urlopen", lambda *a, **kw: io.BytesIO(b"invalid"))
    with pytest.raises(ValueError, match="checksum mismatch"):
        models.download_model(spec)
    assert not models.model_path(spec).exists()
    assert not list(tmp_path.rglob(".download-*"))


def test_download_verified_and_reused_without_network(tmp_path, monkeypatch):
    monkeypatch.setenv("NCF_IMAGE_UPSCALER_HOME", str(tmp_path))
    data = b"valid weights"
    spec = spec_for(data)
    monkeypatch.setattr(models, "urlopen", lambda *a, **kw: io.BytesIO(data))
    destination = models.download_model(spec)
    assert destination.read_bytes() == data

    def forbidden(*args, **kwargs):
        pytest.fail("Installed model was downloaded again")

    monkeypatch.setattr(models, "urlopen", forbidden)
    assert models.download_model(spec) == destination
    assert models.require_model(spec) == destination


def test_legacy_models_migrate_offline_without_overwriting_or_removing_old_files(
    tmp_path, monkeypatch
):
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    monkeypatch.delenv("NCF_IMAGE_UPSCALER_HOME", raising=False)
    monkeypatch.setattr(models, "urlopen", lambda *a, **kw: pytest.fail("Network used"))
    data = b"verified legacy weights"
    spec = spec_for(data)
    legacy = (
        tmp_path
        / "Library/Application Support/image-upscaler/models"
        / spec.id
        / spec.revision
        / "model.safetensors"
    )
    legacy.parent.mkdir(parents=True)
    legacy.write_bytes(data)
    destination = models.require_model(spec)
    assert "ncf-image-upscaler" in str(destination)
    assert destination.read_bytes() == legacy.read_bytes() == data
    destination.write_bytes(b"new installation owns this file")
    with pytest.raises(ValueError, match="corrupted"):
        models.require_model(spec)
    assert destination.read_bytes() == b"new installation owns this file"
    assert legacy.read_bytes() == data
    destination.unlink()
    legacy.write_bytes(b"invalid")
    with pytest.raises(FileNotFoundError):
        models.require_model(spec)
    assert not list(tmp_path.rglob(".migration-*"))


def test_custom_home_never_imports_legacy_models(tmp_path, monkeypatch):
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    monkeypatch.setenv("NCF_IMAGE_UPSCALER_HOME", str(tmp_path / "isolated"))
    data = b"weights"
    spec = spec_for(data)
    legacy = (
        tmp_path
        / "Library/Application Support/image-upscaler/models"
        / spec.id
        / spec.revision
        / "model.safetensors"
    )
    legacy.parent.mkdir(parents=True)
    legacy.write_bytes(data)
    with pytest.raises(FileNotFoundError):
        models.require_model(spec)
    assert not (tmp_path / "isolated").exists()
