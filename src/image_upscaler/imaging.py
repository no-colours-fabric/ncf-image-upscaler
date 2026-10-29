"""Public image-processing API, shared by the native app and CLI."""

import os
import tempfile
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

import numpy as np
from PIL import Image, ImageOps, UnidentifiedImageError
from scipy.ndimage import distance_transform_edt


class ImageEngine(Protocol):
    def upscale(
        self, rgb: np.ndarray, progress: Callable[[], None] | None = None
    ) -> np.ndarray: ...


@dataclass(frozen=True)
class UpscaleResult:
    path: Path
    input_size: tuple[int, int]
    output_size: tuple[int, int]
    has_alpha: bool


def extend_transparent_colors(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """Fill invisible RGB from the closest visible pixel before neural inference.

    PNG stores straight (unassociated) color. Feeding arbitrary black/white
    invisible RGB to a convolutional model contaminates visible edge pixels.
    The alpha channel is never inferred by the RGB model.
    """
    invisible = alpha == 0
    if not invisible.any() or invisible.all():
        return rgb.copy()
    indices = distance_transform_edt(invisible, return_distances=False, return_indices=True)
    result = rgb.copy()
    result[invisible] = rgb[indices[0][invisible], indices[1][invisible]]
    return result


def open_image(path: Path) -> tuple[Image.Image, bytes | None]:
    try:
        with Image.open(path) as source:
            if getattr(source, "n_frames", 1) != 1:
                raise ValueError("Animated and multipage images are not supported.")
            if source.mode in {"I", "F"} or source.mode.startswith("I;16"):
                raise ValueError("Only 8-bit images are supported.")
            icc = source.info.get("icc_profile")
            oriented = ImageOps.exif_transpose(source)
            has_alpha = "A" in oriented.getbands() or "transparency" in oriented.info
            return oriented.convert("RGBA" if has_alpha else "RGB"), icc
    except (UnidentifiedImageError, Image.DecompressionBombError) as error:
        raise ValueError(f"Could not read image: {path}") from error


def default_output(source: Path, scale: int) -> Path:
    return source.with_name(f"{source.stem}_{scale}x.png")


def validate_paths(source: Path, destination: Path, overwrite: bool) -> None:
    if not source.is_file():
        raise FileNotFoundError(f"Input file not found: {source}")
    if destination.suffix.lower() != ".png":
        raise ValueError("Output is saved as PNG. Use the .png file extension.")
    if source.resolve() == destination.resolve():
        raise ValueError("The output file must differ from the original.")
    if destination.exists():
        if source.samefile(destination):
            raise ValueError("The output file points to the original.")
        if not overwrite:
            raise FileExistsError(
                f"File already exists: {destination}. Use --overwrite to replace it."
            )


def save_png(image: Image.Image, path: Path, overwrite: bool, icc: bytes | None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=f".{path.stem}-", suffix=".png", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, "wb") as stream:
            image.save(stream, format="PNG", icc_profile=icc)
            stream.flush()
            os.fsync(stream.fileno())
        if overwrite:
            os.replace(temporary, path)
        else:
            # Atomic no-clobber publication, including a file created during inference.
            os.link(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def upscale_image(
    source: Path,
    destination: Path,
    engine: ImageEngine,
    *,
    scale: int = 4,
    overwrite: bool = False,
    progress: Callable[[], None] | None = None,
) -> UpscaleResult:
    if scale not in (1, 2, 4):
        raise ValueError("Supported scales are 1, 2, and 4.")
    validate_paths(source, destination, overwrite)
    image, icc = open_image(source)
    size = (image.width * scale, image.height * scale)
    alpha = image.getchannel("A") if image.mode == "RGBA" else None
    rgb = np.asarray(image.convert("RGB"))
    if alpha is not None:
        rgb = extend_transparent_colors(rgb, np.asarray(alpha))
    if alpha is not None and not np.asarray(alpha).any():
        output = Image.new("RGBA", size, (0, 0, 0, 0))
    else:
        restored = Image.fromarray(engine.upscale(rgb, progress=progress))
        if restored.mode != "RGB":
            raise ValueError("The engine returned an unsupported image format.")
        # Resize color before attaching alpha: invisible black must not be mixed
        # into visible edge colors. Alpha is resized once, directly to final size.
        if restored.size != size:
            restored = restored.resize(size, Image.Resampling.LANCZOS)
        if alpha is not None:
            scaled_alpha = (
                alpha.copy() if scale == 1 else alpha.resize(size, Image.Resampling.LANCZOS)
            )
            restored.putalpha(scaled_alpha)
            pixels = np.asarray(restored).copy()
            pixels[pixels[:, :, 3] == 0, :3] = 0
            restored = Image.fromarray(pixels)
        output = restored
    save_png(output, destination, overwrite, icc)
    return UpscaleResult(destination, image.size, output.size, alpha is not None)
