import socket

import numpy as np
import pytest
from PIL import Image, ImageDraw

from image_upscaler.engine import MLXEngine
from image_upscaler.imaging import upscale_image
from image_upscaler.models import registry, require_model


def local_weights(spec):
    try:
        return require_model(spec)
    except FileNotFoundError:
        pytest.skip(f"Model {spec.id} not downloaded")


@pytest.mark.integration
@pytest.mark.parametrize(
    ("key", "scale"),
    [
        ("x2plus", 2),
        ("x4plus", 4),
        ("anime", 4),
        ("fast", 4),
        ("x2plus", 1),
        ("anime", 1),
        ("fast", 1),
    ],
)
def test_real_models_preserve_soft_alpha_without_network(key, scale, tmp_path, monkeypatch):
    spec = registry()[key]
    weights = local_weights(spec)

    def deny_network(*args, **kwargs):
        raise AssertionError("Image processing attempted network access")

    monkeypatch.setattr(socket.socket, "connect", deny_network)
    monkeypatch.setattr(socket.socket, "connect_ex", deny_network)
    monkeypatch.setattr(socket, "create_connection", deny_network)
    image = Image.new("RGBA", (45, 37), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((5, 5, 39, 31), fill=(230, 100, 40, 128))
    draw.ellipse((12, 10, 32, 26), fill=(230, 100, 40, 255))
    source = tmp_path / "transparent.png"
    destination = tmp_path / "result.png"
    image.save(source)
    engine = MLXEngine(spec, weights, tile=32)
    upscale_image(source, destination, engine, scale=scale)
    with Image.open(destination) as output:
        assert output.mode == "RGBA"
        assert output.size == (45 * scale, 37 * scale)
        expected_alpha = image.getchannel("A").resize(output.size, Image.Resampling.LANCZOS)
        np.testing.assert_array_equal(output.getchannel("A"), expected_alpha)
        rgb = np.asarray(output)[:, :, :3]
        visible = np.asarray(expected_alpha) > 128
        assert rgb[visible].std() > 0  # actual non-constant neural output
        assert rgb[visible, 0].mean() > rgb[visible, 2].mean()
        if scale == 1:
            assert not np.array_equal(rgb, np.asarray(image)[:, :, :3])


@pytest.mark.integration
def test_invisible_rgb_does_not_change_real_neural_output(tmp_path):
    spec = registry()["fast"]
    engine = MLXEngine(spec, local_weights(spec), tile=32)
    alpha = np.zeros((33, 35), dtype=np.uint8)
    alpha[6:27, 7:28] = 128
    alpha[10:23, 11:24] = 255
    outputs = []
    for index, hidden in enumerate((0, 255)):
        pixels = np.full((33, 35, 4), hidden, dtype=np.uint8)
        pixels[:, :, 3] = alpha
        pixels[alpha > 0, :3] = (220, 90, 30)
        source = tmp_path / f"input{index}.png"
        destination = tmp_path / f"output{index}.png"
        Image.fromarray(pixels).save(source)
        upscale_image(source, destination, engine, scale=4)
        with Image.open(destination) as output:
            outputs.append(np.asarray(output))
    np.testing.assert_array_equal(*outputs)
