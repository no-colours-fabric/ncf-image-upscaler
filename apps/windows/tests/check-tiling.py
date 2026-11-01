"""Bounded comparison of the production tiler and same-artifact full inference."""

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort
from ncf_image_upscaler.imaging import extend_transparent_colors
from onnx_engine import OnnxEngine
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("--bundle", required=True, type=Path)
parser.add_argument("--model-root", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=False)
assert Path(sys.executable).resolve().is_relative_to(args.bundle.resolve())
rows = []
for spec in json.loads((args.bundle / "resources/models.json").read_text()):
    if spec["id"] == "photo2":
        continue  # Photo2 is intentionally full-frame, never this tiled path.
    model = args.model_root / (spec["id"] + "-" + spec["sha256"] + ".onnx")
    with model.open("rb") as file:
        assert hashlib.file_digest(file, "sha256").hexdigest() == spec["sha256"]
    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(model), options, providers=["CPUExecutionProvider"])
    y, x = np.indices((273, 257))
    rgb = np.stack(((x * 13) % 256, (y * 17) % 256, ((x + y) * 23) % 256), axis=2).astype(np.uint8)
    rgb[:, 254:257] = 255
    rgb[254:258, :] = 0
    for mode in ("RGB", "RGBA"):
        data = (
            rgb
            if mode == "RGB"
            else extend_transparent_colors(rgb, ((x * 11 + y * 19) % 256).astype(np.uint8))
        )
        engine = OnnxEngine(session, spec["id"], 4, 4, lambda *a, **kw: None)
        tiled = engine.upscale(data)
        full = np.rint(np.clip(engine.forward(data), 0, 1) * 255).astype(np.uint8)
        difference = np.abs(tiled.astype(np.int16) - full.astype(np.int16))
        row = dict(
            artifact=spec["id"],
            sha256=spec["sha256"],
            mode=mode,
            input=[257, 273],
            tile=256,
            context=64,
            edge="context clipped to global image; native convolution zero padding",
            max_uint8=int(difference.max()),
            mean_uint8=float(difference.mean()),
            tolerance="max<=2 and mean<=0.02 uint8 levels",
            passed=bool(difference.max() <= 2 and difference.mean() <= 0.02),
        )
        Image.fromarray(tiled).save(args.output / (spec["id"] + "-" + mode + ".png"))
        Image.fromarray(np.minimum(difference * 32, 255).astype(np.uint8)).save(
            args.output / (spec["id"] + "-" + mode + "-difference32.png")
        )
        rows.append(row)
        print(json.dumps(row), flush=True)
    del session
(args.output / "tiling.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")
assert all(row["passed"] for row in rows), "New graph tiling failed; do not use for larger inputs"
