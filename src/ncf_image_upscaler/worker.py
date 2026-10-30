"""JSON-lines bridge for the native app. Local inference only; no downloads."""

import argparse
import json
import math
import sys
import time
from pathlib import Path

from .engine import MLXEngine
from .imaging import open_image, upscale_image
from .models import choose_model, require_model


def emit(event: str, **values) -> None:
    print(json.dumps({"event": event, **values}, ensure_ascii=False), flush=True)


def run(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Native ncf-image-upscaler worker")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scale", type=int, choices=(1, 2, 4), default=4)
    parser.add_argument("--model", choices=("photo", "anime", "fast"), default="photo")
    parser.add_argument("--tile", type=int, default=256)
    args = parser.parse_args(argv)
    source = args.input.expanduser().resolve()
    destination = args.output.expanduser().absolute()
    image, _ = open_image(source)
    spec = choose_model(args.model, args.scale)
    weights = require_model(spec)
    # Match the vendored runner's pre-padding and x2 modulus padding.
    width, height = image.width + 10, image.height + 10
    if spec.scale == 2:
        width += width % 2
        height += height % 2
    total = math.ceil(width / args.tile) * math.ceil(height / args.tile)
    started = time.monotonic()
    emit("started", total=total, width=image.width, height=image.height)
    engine = MLXEngine(spec, weights, tile=args.tile)
    completed = 0

    def progress():
        nonlocal completed
        completed += 1
        emit("progress", completed=completed, total=total)

    result = upscale_image(source, destination, engine, scale=args.scale, progress=progress)
    emit(
        "completed",
        path=str(result.path),
        width=result.output_size[0],
        height=result.output_size[1],
        scale=args.scale,
        model=args.model,
        seconds=round(time.monotonic() - started, 3),
    )
    return 0


def main() -> int:
    try:
        return run()
    except KeyboardInterrupt:
        emit("cancelled")
        return 130
    except Exception as error:
        emit("error", message=str(error))
        return 1


if __name__ == "__main__":
    sys.exit(main())
