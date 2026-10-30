import hashlib
import io
import json
from dataclasses import replace

from ncf_image_upscaler import models, setup_models


def test_status_never_downloads_and_detects_corruption(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("NCF_IMAGE_UPSCALER_HOME", str(tmp_path))
    payload = b"verified weights"
    original = next(iter(models.registry().values()))
    spec = replace(original, size=len(payload), sha256=hashlib.sha256(payload).hexdigest())
    monkeypatch.setattr(setup_models, "registry", lambda: {spec.id: spec})
    monkeypatch.setattr(
        models,
        "urlopen",
        lambda *a, **kw: (_ for _ in ()).throw(AssertionError("Unexpected network")),
    )
    assert setup_models.run(["--status"]) == 0
    assert not tmp_path.joinpath("models").exists()
    events = [json.loads(line) for line in capsys.readouterr().out.splitlines()]
    assert events[0]["models"][0]["installed"] is False
    destination = models.model_path(spec)
    destination.parent.mkdir(parents=True)
    destination.write_bytes(payload)
    assert setup_models.status()[0]["installed"] is True
    destination.write_bytes(b"corrupt")
    assert setup_models.status()[0]["installed"] is False


def test_explicit_download_reports_progress_and_verified_status(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("NCF_IMAGE_UPSCALER_HOME", str(tmp_path))
    payload = b"verified weights"
    original = next(iter(models.registry().values()))
    spec = replace(original, size=len(payload), sha256=hashlib.sha256(payload).hexdigest())
    monkeypatch.setattr(setup_models, "registry", lambda: {spec.id: spec})
    monkeypatch.setattr(models, "urlopen", lambda *a, **kw: io.BytesIO(payload))
    assert setup_models.run(["--download"]) == 0
    events = [json.loads(line) for line in capsys.readouterr().out.splitlines()]
    progress = [event for event in events if event["event"] == "progress"]
    assert progress[-1]["completed"] == progress[-1]["total"] == len(payload)
    assert (
        next(event for event in events if event["event"] == "status")["models"][0]["installed"]
        is True
    )
    assert events[-1]["event"] == "completed"
