#!/usr/bin/env python3
"""Inspect release archives without importing MLX or accessing the network."""

import sys
import tarfile
import zipfile
from pathlib import Path


def check_names(names: set[str], *, wheel: bool) -> None:
    for name in names:
        path = Path(name)
        forbidden = {"work", "outputs", ".venv", ".git", "__pycache__", "models"}
        if (
            forbidden.intersection(path.parts)
            or path.suffix
            in {
                ".safetensors",
                ".npz",
                ".pt",
                ".pth",
                ".pyc",
                ".pem",
                ".key",
                ".p12",
            }
            or path.name == ".env"
            or path.name.startswith(".env.")
        ):
            raise SystemExit(f"Unexpected local or binary artifact in distribution: {name}")
    required = {
        "LICENSE",
        "THIRD_PARTY.md",
        "Real-ESRGAN-BSD-3-Clause.txt",
        "BasicSR-Apache-2.0.txt",
    }
    missing = required - {Path(name).name for name in names}
    if missing:
        raise SystemExit(f"Missing license files: {sorted(missing)}")
    prefix = "image_upscaler/" if wheel else "src/image_upscaler/"
    if prefix + "models.json" not in names:
        raise SystemExit("Pinned model manifest missing")
    if prefix + "_vendor/realesrgan_mlx/archs/rrdbnet_arch.py" not in names:
        raise SystemExit("Vendored architecture missing")
    if not wheel:
        for required_path in (
            "scripts/install.sh",
            "scripts/build-app.sh",
            "uv.lock",
            "native/Sources/ThumbnailCache.swift",
            "README.md",
        ):
            if required_path not in names:
                raise SystemExit(f"Source archive missing {required_path}")


def main() -> None:
    directory = Path(sys.argv[1])
    wheels = sorted(directory.glob("*.whl"))
    sources = sorted(directory.glob("*.tar.gz"))
    if len(wheels) != 1 or len(sources) != 1:
        raise SystemExit("Expected exactly one wheel and one source archive")
    with zipfile.ZipFile(wheels[0]) as archive:
        check_names(set(archive.namelist()), wheel=True)
    with tarfile.open(sources[0], "r:gz") as archive:
        entries = [member for member in archive.getmembers() if member.isfile()]
        names = {str(Path(*Path(member.name).parts[1:])) for member in entries}
        check_names(names, wheel=False)
        installer = next(
            member for member in entries if member.name.endswith("/scripts/install.sh")
        )
        if not installer.mode & 0o111:
            raise SystemExit("Source installer must be executable")
    print("Distribution checks passed: manifests, vendored code, licenses, and source installer")


if __name__ == "__main__":
    main()
