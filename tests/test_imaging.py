import numpy as np
import pytest
from PIL import Image

from image_upscaler.imaging import extend_transparent_colors, upscale_image


class NearestEngine:
    """Predictable adapter to isolate alpha/file handling from model inference."""

    def __init__(self, scale=4):
        self.scale = scale
        self.received = None

    def upscale(self, rgb, progress=None):
        self.received = rgb
        return np.asarray(
            Image.fromarray(rgb).resize(
                (rgb.shape[1] * self.scale, rgb.shape[0] * self.scale),
                Image.Resampling.NEAREST,
            )
        )


def test_invisible_colors_do_not_contaminate_model_input():
    alpha = np.zeros((5, 7), dtype=np.uint8)
    alpha[1:4, 2:5] = 128
    first = np.zeros((5, 7, 3), dtype=np.uint8)
    first[alpha > 0] = (230, 80, 40)
    second = first.copy()
    second[alpha == 0] = (255, 255, 255)
    expected = np.full_like(first, (230, 80, 40))
    np.testing.assert_array_equal(extend_transparent_colors(first, alpha), expected)
    np.testing.assert_array_equal(extend_transparent_colors(second, alpha), expected)


@pytest.mark.parametrize("mode", ["RGBA", "LA", "P"])
@pytest.mark.parametrize("scale", [1, 2])
def test_soft_alpha_preserved_at_final_size(tmp_path, mode, scale):
    alpha = np.tile(np.array([0, 0, 64, 128, 192, 255, 255], dtype=np.uint8), (5, 1))
    image = Image.new("RGBA", (7, 5), (210, 100, 50, 255))
    image.putalpha(Image.fromarray(alpha))
    if mode == "LA":
        image = image.convert("LA")
    elif mode == "P":
        image = image.quantize(colors=16)
    source = tmp_path / "input.png"
    destination = tmp_path / "output.png"
    image.save(source)
    original_alpha = image.convert("RGBA").getchannel("A")
    engine = NearestEngine(4)
    result = upscale_image(source, destination, engine, scale=scale)
    with Image.open(destination) as output:
        assert output.mode == "RGBA"
        assert output.size == (7 * scale, 5 * scale)
        expected = original_alpha.resize(output.size, Image.Resampling.LANCZOS)
        np.testing.assert_array_equal(np.asarray(output.getchannel("A")), np.asarray(expected))
        values = np.asarray(output.getchannel("A"))
        assert ((values > 0) & (values < 255)).any()
    assert result.has_alpha
    assert result.input_size == (7, 5)


def test_same_size_enhancement_uses_model_and_preserves_alpha(tmp_path):
    source = tmp_path / "input.png"
    image = Image.new("RGBA", (7, 5), (80, 40, 20, 128))
    image.putpixel((0, 0), (255, 255, 255, 0))
    image.save(source)

    class RestorationEngine(NearestEngine):
        def upscale(self, rgb, progress=None):
            restored = super().upscale(rgb, progress)
            return np.clip(restored.astype(np.int16) + 30, 0, 255).astype(np.uint8)

    engine = RestorationEngine(2)
    destination = tmp_path / "result.png"
    result = upscale_image(source, destination, engine, scale=1)
    assert engine.received is not None
    assert result.input_size == result.output_size == image.size
    with Image.open(destination) as output:
        np.testing.assert_array_equal(output.getchannel("A"), image.getchannel("A"))
        assert output.getpixel((3, 2)) == (110, 70, 50, 128)


def test_rgb_transparent_color_is_respected(tmp_path):
    image = Image.new("RGB", (7, 5), (255, 0, 0))
    image.putpixel((3, 2), (0, 255, 0))
    source = tmp_path / "input.png"
    image.save(source, transparency=(255, 0, 0))
    destination = tmp_path / "output.png"
    upscale_image(source, destination, NearestEngine())
    with Image.open(destination) as output:
        assert output.mode == "RGBA"
        # Reload to apply PNG's transparent-color metadata, which is absent
        # on the in-memory source object before save.
        with Image.open(source) as saved:
            expected = saved.convert("RGBA").getchannel("A")
        expected = expected.resize(output.size, Image.Resampling.LANCZOS)
        np.testing.assert_array_equal(output.getchannel("A"), expected)
        assert output.getchannel("A").getextrema()[0] == 0
        assert output.getchannel("A").getextrema()[1] > 0


def test_transparent_image_never_calls_model(tmp_path):
    source = tmp_path / "input.png"
    Image.new("RGBA", (7, 5), (255, 100, 50, 0)).save(source)
    engine = NearestEngine()
    destination = tmp_path / "output.png"
    upscale_image(source, destination, engine)
    assert engine.received is None
    with Image.open(destination) as output:
        assert np.asarray(output).max() == 0


def test_never_overwrites_source_or_existing_result(tmp_path):
    source = tmp_path / "input.png"
    Image.new("RGB", (7, 5)).save(source)
    original = source.read_bytes()
    for overwrite in (False, True):
        with pytest.raises(ValueError):
            upscale_image(source, source, NearestEngine(), overwrite=overwrite)
    alias = tmp_path / "alias.png"
    alias.hardlink_to(source)
    with pytest.raises(ValueError):
        upscale_image(source, alias, NearestEngine(), overwrite=True)
    destination = tmp_path / "output.png"
    destination.write_bytes(b"existing file")
    with pytest.raises(FileExistsError):
        upscale_image(source, destination, NearestEngine())
    assert destination.read_bytes() == b"existing file"
    assert source.read_bytes() == original


def test_exif_orientation_applied(tmp_path):
    image = Image.new("RGB", (7, 5))
    exif = image.getexif()
    exif[274] = 6
    source = tmp_path / "rotated.jpg"
    image.save(source, exif=exif)
    destination = tmp_path / "result.png"
    result = upscale_image(source, destination, NearestEngine(), scale=2)
    assert result.input_size == (5, 7)
    assert result.output_size == (10, 14)


def test_animation_rejected(tmp_path):
    source = tmp_path / "input.gif"
    Image.new("RGB", (5, 5), "red").save(
        source, save_all=True, append_images=[Image.new("RGB", (5, 5), "blue")], duration=100
    )
    with pytest.raises(ValueError, match="Animated"):
        upscale_image(source, tmp_path / "output.png", NearestEngine())


def test_atomic_save_does_not_clobber_a_racing_file(tmp_path):
    source = tmp_path / "input.png"
    Image.new("RGB", (5, 5)).save(source)
    destination = tmp_path / "output.png"

    class RacingEngine(NearestEngine):
        def upscale(self, rgb, progress=None):
            destination.write_bytes(b"created during inference")
            return super().upscale(rgb, progress)

    with pytest.raises(FileExistsError):
        upscale_image(source, destination, RacingEngine())
    assert destination.read_bytes() == b"created during inference"
    assert not list(tmp_path.glob(".output-*.png"))


def test_jpeg_output_rejected(tmp_path):
    source = tmp_path / "input.png"
    Image.new("RGBA", (5, 5)).save(source)
    with pytest.raises(ValueError, match="PNG"):
        upscale_image(source, tmp_path / "output.jpg", NearestEngine())
