import subprocess
import sys

import numpy as np
import pytest
from PIL import Image

from image_upscaler.models import choose_model, require_model


@pytest.mark.integration
def test_same_size_cli_preserves_source_and_uses_1x_filename(tmp_path):
    try:
        require_model(choose_model("photo", 1))
    except FileNotFoundError:
        pytest.skip("x2plus not installed")
    source = tmp_path / "photo with spaces.png"
    image = Image.new("RGBA", (45, 37), (220, 80, 30, 128))
    image.save(source)
    original = source.read_bytes()
    command = [sys.executable, "-m", "image_upscaler", str(source), "--scale", "1", "--quiet"]
    process = subprocess.run(command, capture_output=True, text=True, timeout=60)
    assert process.returncode == 0, process.stderr
    destination = source.with_name("photo with spaces_1x.png")
    assert process.stdout.strip() == str(destination)
    with Image.open(destination) as output:
        assert output.size == image.size
        np.testing.assert_array_equal(output.getchannel("A"), image.getchannel("A"))
    result = destination.read_bytes()
    repeated = subprocess.run(command, capture_output=True, text=True, timeout=60)
    assert repeated.returncode == 1
    assert "--overwrite" in repeated.stderr
    assert source.read_bytes() == original
    assert destination.read_bytes() == result
