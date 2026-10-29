"""Small CLI adapter. Network use is confined to `models download`."""

import argparse
import sys
import time
from pathlib import Path

from . import __version__
from .models import choose_model, download_model, model_path, registry, require_model
from .paths import app_home


def models_command(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="upscale models", description="Local models")
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("list", help="list models and their locations")
    download = sub.add_parser("download", help="download models without an account")
    download.add_argument("model", choices=[*registry(), "all"])
    verify = sub.add_parser("verify", help="verify installed model SHA-256 hashes")
    verify.add_argument("model", nargs="?", default="all", choices=[*registry(), "all"])
    args = parser.parse_args(argv)
    specs = registry()
    if args.action == "list":
        for spec in specs.values():
            status = "installed" if model_path(spec).is_file() else "not downloaded"
            print(f"{spec.id:8} {spec.size / 1_000_000:5.1f} MB  {status}  {spec.title}")
        print(f"\nFolder: {app_home() / 'models'}")
        return 0
    selected = specs.values() if args.model == "all" else [specs[args.model]]
    for spec in selected:
        print(
            f"{'Downloading' if args.action == 'download' else 'Verification'}: {spec.title}",
            file=sys.stderr,
            flush=True,
        )
        path = download_model(spec) if args.action == "download" else require_model(spec)
        print(f"OK {spec.id}: {path}")
    return 0


def doctor() -> int:
    import platform

    from .engine import mlx_runtime

    mx = mlx_runtime()

    available = mx.metal.is_available()
    print(f"Image Upscaler {__version__}")
    print(f"System: {platform.system()} {platform.machine()}")
    print(f"Python: {platform.python_version()}")
    print(f"Apple GPU: {'available' if available else 'unavailable'}")
    print(f"Data: {app_home()}")
    print(f"Environment: {sys.prefix}")
    return 0 if available else 1


def run(argv: list[str]) -> int:
    if argv and argv[0] == "models":
        return models_command(argv[1:])
    if argv == ["doctor"]:
        return doctor()
    parser = argparse.ArgumentParser(
        prog="upscale",
        description="Offline AI image enhancement at ×1/×2/×4, preserving transparency.",
        epilog=(
            "Models: upscale models list | upscale models download all. Diagnostics: upscale doctor"
        ),
    )
    parser.add_argument("input", type=Path, help="path to an image")
    parser.add_argument(
        "--scale",
        type=int,
        choices=[1, 2, 4],
        default=4,
        help="output scale: 1 enhances at original size, 2/4 upscale (default: 4)",
    )
    parser.add_argument(
        "--model",
        choices=["photo", "anime", "fast"],
        default="photo",
        help="model preset (default: photo)",
    )
    parser.add_argument(
        "-o", "--output", type=Path, help="output PNG (default: next to the original)"
    )
    parser.add_argument(
        "--tile", type=int, default=256, help="even tile size, at least 32 (default: 256)"
    )
    parser.add_argument(
        "--overwrite", action="store_true", help="allow replacing an existing output file"
    )
    parser.add_argument("--quiet", action="store_true", help="print only the output path")
    parser.add_argument("--version", action="version", version=f"Image Upscaler {__version__}")
    args = parser.parse_args(argv)
    if args.tile < 32 or args.tile % 2:
        parser.error("--tile must be an even number of at least 32")

    from .engine import MLXEngine
    from .imaging import default_output, upscale_image, validate_paths

    source = args.input.expanduser().resolve()
    destination = (
        args.output.expanduser().absolute() if args.output else default_output(source, args.scale)
    )
    validate_paths(source, destination, args.overwrite)
    spec = choose_model(args.model, args.scale)
    weights = require_model(spec)
    if not args.quiet:
        print(
            f"{spec.title}. Scale ×{args.scale}. Processing on Apple GPU…",
            file=sys.stderr,
            flush=True,
        )
    started = time.monotonic()
    engine = MLXEngine(spec, weights, tile=args.tile)
    completed = 0

    def progress():
        nonlocal completed
        completed += 1
        if not args.quiet:
            print(f"\rTiles processed: {completed}", end="", file=sys.stderr, flush=True)

    result = upscale_image(
        source, destination, engine, scale=args.scale, overwrite=args.overwrite, progress=progress
    )
    if not args.quiet:
        width, height = result.output_size
        print(
            f"\nDone: {width}×{height}, {time.monotonic() - started:.1f} s"
            f"{' · transparency preserved' if result.has_alpha else ''}",
            file=sys.stderr,
        )
    print(result.path)
    return 0


def main(argv: list[str] | None = None) -> int:
    try:
        return run(sys.argv[1:] if argv is None else argv)
    except KeyboardInterrupt:
        print("\nCancelled.", file=sys.stderr)
        return 130
    except (OSError, ValueError, RuntimeError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
