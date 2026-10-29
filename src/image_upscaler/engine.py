"""MLX adapter; no download code, CLI, or image-file handling here."""

from collections.abc import Callable
from pathlib import Path

import numpy as np

from .models import ModelSpec


def mlx_runtime():
    try:
        import mlx.core as mx
    except ImportError as error:
        raise RuntimeError(
            "Could not initialize Apple GPU support. "
            "Run the program in a macOS terminal on Apple Silicon. "
            f"Details: {error}"
        ) from error
    if not mx.metal.is_available():
        raise RuntimeError("MLX cannot access an Apple GPU. macOS on Apple Silicon is required.")
    return mx


class MLXEngine:
    def __init__(self, spec: ModelSpec, weights: Path, tile: int = 256):
        mx = mlx_runtime()

        from ._vendor.realesrgan_mlx.archs import RRDBNet, SRVGGNetCompact
        from ._vendor.realesrgan_mlx.utils.realesrganer import RealESRGANer

        if tile < 32 or tile % 2:
            raise ValueError("Tile size must be an even number of at least 32.")
        mx.set_cache_limit(512 * 1024 * 1024)
        if spec.architecture == "rrdb":
            model = RRDBNet(scale=spec.scale, num_block=spec.blocks)
        else:
            model = SRVGGNetCompact(num_conv=spec.blocks, upscale=spec.scale)
        model.load_weights(list(mx.load(str(weights)).items()), strict=True)
        model.eval()
        mx.eval(model.parameters())

        class Runner(RealESRGANer):
            def _infer(self, nhwc):
                output = self.model(mx.array(nhwc, dtype=mx.float16))
                mx.eval(output)
                result = np.asarray(output, dtype=np.float32)
                if self.progress:
                    self.progress()
                return result

        self.runner = Runner(model, spec.scale, tile=tile, tile_pad=32, pre_pad=10)
        self.runner.progress = None

    def upscale(self, rgb: np.ndarray, progress: Callable[[], None] | None = None) -> np.ndarray:
        self.runner.progress = progress
        output, _ = self.runner.enhance(rgb)
        return output
