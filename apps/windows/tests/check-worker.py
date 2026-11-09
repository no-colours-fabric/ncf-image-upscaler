"""Small installed-runtime functional matrix; requires already prepared models."""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageCms, ImageOps

parser = argparse.ArgumentParser()
parser.add_argument("--bundle", type=Path, required=True)
parser.add_argument("--model-root", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
root, models, out = args.bundle.resolve(), args.model_root.resolve(), args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
assert Path(sys.executable).resolve().is_relative_to(root)
assert all(Path(path).resolve().is_relative_to(root) for path in sys.path)
icc = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
fixtures = []
for mode, size in [("RGB", (27, 19)), ("RGBA", (33, 25))]:
    image = Image.new(mode, size)
    pixels = image.load()
    for y in range(size[1]):
        for x in range(size[0]):
            rgb = ((x * 17) % 256, (y * 23) % 256, ((x + y) * 29) % 256)
            pixels[x, y] = rgb if mode == "RGB" else rgb + ((x * 11 + y * 19) % 256,)
    exif = Image.Exif()
    if mode == "RGB":
        exif[274] = 6
    path = out / (mode + " Unicode образец.png")
    image.save(path, icc_profile=icc, exif=exif)
    fixtures.append(path)


def sha(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def launch(source, destination, preset, scale):
    command = [
        sys.executable,
        str(root / "engine/launcher.py"),
        "--input",
        str(source),
        "--output",
        str(destination),
        "--model",
        preset,
        "--scale",
        str(scale),
        "--backend",
        "cpu",
        "--model-root",
        str(models),
    ]
    started = time.perf_counter()
    result = subprocess.run(
        command,
        input="",
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
        cwd=os.environ["WINDIR"],
    )
    events = [json.loads(line) for line in result.stdout.splitlines()]
    return result, events, time.perf_counter() - started


rows = []
for source in fixtures:
    original = sha(source)
    with Image.open(source) as opened:
        expected = ImageOps.exif_transpose(opened).convert(opened.mode)
    for preset in ("photo", "illustration", "fast"):
        for scale in (1, 2, 4):
            destination = out / (source.stem + "-" + preset + "-" + str(scale) + ".png")
            result, events, wall = launch(source, destination, preset, scale)
            completed = next((e for e in events if e["event"] == "completed"), None)
            assert result.returncode == 0 and completed, result.stdout + result.stderr
            assert any(e["event"] == "progress" for e in events), "No real neural call"
            with Image.open(destination) as final:
                final.load()
                assert final.size == (expected.width * scale, expected.height * scale)
                assert final.mode == expected.mode
                assert final.info.get("icc_profile") == icc
                assert final.getexif().get(274, 1) == 1
                if expected.mode == "RGBA":
                    np.testing.assert_array_equal(
                        final.getchannel("A"),
                        expected.getchannel("A").resize(final.size, Image.Resampling.LANCZOS),
                    )
                dimensions = list(final.size)
            assert sha(source) == original
            output_hash = sha(destination)
            blocked, _, _ = launch(source, destination, preset, scale)
            assert blocked.returncode != 0 and sha(destination) == output_hash
            rows.append(
                dict(
                    input=source.name,
                    mode=expected.mode,
                    normalized=list(expected.size),
                    preset=preset,
                    scale=scale,
                    artifact=completed["artifact"],
                    artifact_sha256=completed.get("artifact_sha256"),
                    output=destination.name,
                    dimensions=dimensions,
                    decode=True,
                    alpha_exact=expected.mode == "RGBA",
                    icc=True,
                    orientation=True,
                    source_unchanged=True,
                    existing_output_protected=True,
                    neural_call=True,
                    exit=0,
                    processing_seconds=completed["seconds"],
                    wall_seconds=round(wall, 3),
                    output_sha256=output_hash,
                )
            )
            print("PASS", source.name, preset, scale, flush=True)
    blocked, _, _ = launch(source, source, "fast", 1)
    assert blocked.returncode != 0 and sha(source) == original
    alias = out / (source.stem + "-hardlink.png")
    os.link(source, alias)
    blocked, _, _ = launch(source, alias, "fast", 1)
    assert blocked.returncode != 0 and sha(source) == original
(out / "matrix.json").write_text(json.dumps(rows, indent=2, ensure_ascii=False), encoding="utf-8")
print(
    json.dumps(
        {
            "passed": len(rows),
            "fail": 0,
            "runtime_isolated": True,
            "actual_neural_calls": len(rows),
            "source_and_hardlink_protected": True,
        }
    )
)
