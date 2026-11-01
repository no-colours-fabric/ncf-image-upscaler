"""Local Windows worker. Processing never downloads models or dependencies."""

import argparse
import hashlib
import json
import math
import os
import sys
import time
from pathlib import Path


def emit(event, **data):
    print(json.dumps({"event": event, **data}, ensure_ascii=True), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--model-root",
        type=Path,
        default=Path(os.environ["LOCALAPPDATA"]) / "NCF Image Upscaler/models",
    )
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--model", choices=["photo", "illustration", "fast"], required=True)
    parser.add_argument("--scale", type=int, choices=[1, 2, 4], required=True)
    args = parser.parse_args()
    import onnxruntime as ort
    from ncf_image_upscaler.imaging import open_image, upscale_image, validate_paths

    validate_paths(args.input, args.output, False)
    bundle = Path(__file__).resolve().parents[1]
    key = ("photo4" if args.scale == 4 else "photo2") if args.model == "photo" else args.model
    registry = {
        item["id"]: item for item in json.loads((bundle / "resources/models.json").read_text())
    }
    spec = registry[key]
    native = spec["native_scale"]
    model = args.model_root / (key + "-" + spec["sha256"] + ".onnx")
    if not model.is_file():
        raise RuntimeError(
            "The selected model is not installed. Open Models and choose Download / Repair Models."
        )
    image, _ = open_image(args.input)
    width, height = image.size
    image.close()
    total = 1 if key == "photo2" else math.ceil(width / 256) * math.ceil(height / 256)
    emit(
        "started",
        width=width,
        height=height,
        total=total,
        model=args.model,
        scale=args.scale,
        backend="CPU",
    )
    if hashlib.sha256(model.read_bytes()).hexdigest() != spec["sha256"]:
        raise RuntimeError(
            "The installed model failed its integrity check. "
            "Open Models and choose Download / Repair Models."
        )
    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(
        str(model), sess_options=options, providers=["CPUExecutionProvider"]
    )
    if session.get_providers() != ["CPUExecutionProvider"]:
        raise RuntimeError("Could not select the local CPU backend.")
    emit(
        "ready",
        total=total,
        backend="CPU",
        inference_mode="full_frame" if key == "photo2" else "tiled",
    )
    from onnx_engine import OnnxEngine

    started = time.perf_counter()
    emit("phase", phase="preparing_image")
    result = upscale_image(
        args.input, args.output, OnnxEngine(session, key, native, total, emit), scale=args.scale
    )
    emit(
        "completed",
        path=str(result.path),
        width=result.output_size[0],
        height=result.output_size[1],
        seconds=round(time.perf_counter() - started, 3),
        alpha=result.has_alpha,
        model=args.model,
        scale=args.scale,
        artifact=key,
        artifact_sha256=spec["sha256"],
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        emit("error", message=str(error))
        import traceback

        traceback.print_exc(file=sys.stderr)
        sys.exit(1)
