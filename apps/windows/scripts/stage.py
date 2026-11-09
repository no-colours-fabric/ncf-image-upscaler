"""Offline assembly from explicitly prepared, hash-locked dependencies."""

import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

app = Path(__file__).resolve().parents[1]
repo = app.parents[1]


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def unpack(path, target, digest):
    if sha(path) != digest:
        raise ValueError(f"Dependency integrity failure: {path.name}")
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            parts = Path(entry.filename).parts
            if entry.is_dir():
                continue
            if entry.filename.startswith("/") or ".." in parts or ":" in entry.filename:
                raise ValueError("Unsafe archive member")
            if any(
                part in ("__pycache__", "tests", "test", "datasets") for part in parts
            ) or entry.filename.endswith((".pyc", ".npz", ".pth", ".onnx", ".pt", ".safetensors")):
                continue
            # Standard wheel .data/purelib and .data/platlib schemes.
            if parts[0].endswith(".data"):
                if len(parts) < 3 or parts[1] not in ("purelib", "platlib"):
                    continue
                parts = parts[2:]
            destination = target.joinpath(*parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(entry) as source, destination.open("wb") as out:
                shutil.copyfileobj(source, out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", required=True, type=Path)
    parser.add_argument("--stage", required=True, type=Path)
    args = parser.parse_args()
    stage = args.stage.resolve()
    if stage.exists():
        raise ValueError("Stage must be a NEW directory; existing builds are preserved")
    stage.mkdir(parents=True)
    tools = json.loads((app / "toolchain.json").read_text())
    runtime = stage / "runtime"
    unpack(args.cache / tools["python"]["file"], runtime, tools["python"]["sha256"])
    for wheel in json.loads((app / "wheels.json").read_text(encoding="utf-8-sig")):
        unpack(args.cache / wheel["filename"], runtime / "Lib/site-packages", wheel["sha256"])
    (runtime / "python311._pth").write_text(
        "python311.zip\n.\nLib\\site-packages\n..\\engine\n", encoding="ascii"
    )
    shutil.copytree(
        app / "engine", stage / "engine", ignore=shutil.ignore_patterns("__pycache__", "*.pyc")
    )
    package = stage / "engine/ncf_image_upscaler"
    package.mkdir()
    for name in ["__init__.py", "imaging.py"]:
        shutil.copy2(repo / "src/ncf_image_upscaler" / name, package / name)
    shutil.copytree(app / "resources", stage / "resources")
    shutil.copy2(app / "models.json", stage / "resources/models.json")
    shutil.copy2(app / "native-components.json", stage / "resources/native-components.json")
    shutil.copytree(repo / "licenses", stage / "licenses")
    for name in ["LICENSE", "THIRD_PARTY.md"]:
        shutil.copy2(repo / name, stage / "licenses" / name)
    shutil.copy2(app / "resources/icons/LICENSE.txt", stage / "licenses/Lucide-LICENSE.txt")
    shutil.copy2(
        app / "resources/icons/Feather-MIT-LICENSE.txt", stage / "licenses/Feather-MIT-LICENSE.txt"
    )
    shutil.copy2(app / "README.md", stage / "README.md")
    shutil.copy2(app / "VERSION", stage / "VERSION")
    shutil.copy2(
        app / "resources/notices/Microsoft-DirectML-LICENSE.txt",
        stage / "licenses/Microsoft-DirectML-LICENSE.txt",
    )
    (stage / "licenses/WINDOWS-NOTICES.txt").write_text(
        "NCF Image Upscaler: BSD-3-Clause. CPython: runtime/LICENSE.txt. "
        "ONNX Runtime, NumPy, Pillow, SciPy and transitive dependencies retain their "
        "license/NOTICE files in runtime/Lib/site-packages. DirectML native runtime is "
        "covered by the included Microsoft DirectML software license, not the ORT MIT license. "
        "Lucide and Feather "
        "notices accompany the unchanged SVGs. Model weights are NOT bundled; "
        "explicit Hugging Face preparation is required. Downloaded Real-ESRGAN "
        "weights retain their upstream BSD-3-Clause terms. See model-cards.\n",
        encoding="utf-8",
    )
    # No model or developer environment may enter the installer payload.
    forbidden = {".onnx", ".pth", ".pt", ".safetensors", ".npz", ".partial"}
    assert not any(p.suffix.lower() in forbidden for p in stage.rglob("*") if p.is_file())
    assert not (stage / "models").exists()
    assert not (runtime / "pyvenv.cfg").exists()
    print(stage)


if __name__ == "__main__":
    main()
