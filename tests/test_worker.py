import json
import subprocess
import sys

import pytest
from PIL import Image

from image_upscaler.models import choose_model, require_model


@pytest.mark.integration
@pytest.mark.parametrize("scale", [1, 2])
def test_native_worker_emits_progress_and_result(tmp_path, scale):
    try:
        require_model(choose_model("photo", 2))
    except FileNotFoundError:
        pytest.skip("x2plus not installed")
    source = tmp_path / "original with spaces.png"
    destination = tmp_path / "temporary result.png"
    Image.new("RGBA", (45, 37), (220, 80, 30, 128)).save(source)
    process = subprocess.run(
        [
            sys.executable,
            "-m",
            "image_upscaler.worker",
            "--input",
            str(source),
            "--output",
            str(destination),
            "--scale",
            str(scale),
            "--tile",
            "32",
        ],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert process.returncode == 0, process.stderr + process.stdout
    events = [json.loads(line) for line in process.stdout.splitlines()]
    assert events[0]["event"] == "started"
    progress = [event for event in events if event["event"] == "progress"]
    assert len(progress) == events[0]["total"]
    assert progress[-1]["completed"] == progress[-1]["total"]
    assert events[-1]["event"] == "completed"
    assert events[-1]["path"] == str(destination)
    assert events[-1]["scale"] == scale
    with Image.open(destination) as result:
        assert result.mode == "RGBA"
        assert result.size == (45 * scale, 37 * scale)
        assert result.getchannel("A").getextrema() == (128, 128)


def test_native_worker_missing_model_fails_without_network(tmp_path):
    import os

    source = tmp_path / "original.png"
    Image.new("RGB", (5, 5)).save(source)
    process = subprocess.run(
        [
            sys.executable,
            "-m",
            "image_upscaler.worker",
            "--input",
            str(source),
            "--output",
            str(tmp_path / "output.png"),
        ],
        env={**os.environ, "IMAGE_UPSCALER_HOME": str(tmp_path / "missing-runtime")},
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert process.returncode == 1
    event = json.loads(process.stdout)
    assert event["event"] == "error"
    assert "is not installed" in event["message"]
    assert not (tmp_path / "output.png").exists()
