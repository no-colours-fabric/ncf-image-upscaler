import hashlib
import io
from dataclasses import replace

import pytest

from image_upscaler import models


def spec_for(data):
    return replace(
        next(iter(models.registry().values())),
        size=len(data),
        sha256=hashlib.sha256(data).hexdigest(),
    )


def test_missing_and_corrupt_models_never_trigger_network(tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_UPSCALER_HOME", str(tmp_path))

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
    monkeypatch.setenv("IMAGE_UPSCALER_HOME", str(tmp_path))
    spec = spec_for(b"correct")
    monkeypatch.setattr(models, "urlopen", lambda *a, **kw: io.BytesIO(b"invalid"))
    with pytest.raises(ValueError, match="checksum mismatch"):
        models.download_model(spec)
    assert not models.model_path(spec).exists()
    assert not list(tmp_path.rglob(".download-*"))


def test_download_verified_and_reused_without_network(tmp_path, monkeypatch):
    monkeypatch.setenv("IMAGE_UPSCALER_HOME", str(tmp_path))
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
