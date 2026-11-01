---
license: bsd-3-clause
tags:
  - skillsafe
  - browser
  - onnxruntime-web
  - image-super-resolution
  - onnx
---

# Real-ESRGAN x2plus (RRDBNet 23 blocks, 2x)

Browser-ready `onnx` artifacts for **image-super-resolution**, produced by SkillSafe's
reproducible converter ([`models/` in skillsafe.ai](https://github.com/skillsafe-admin/skillsafe.ai-website/tree/main/models))
from a pinned upstream source. Every byte here is derivable from that source plus
the recipe below; nothing was edited by hand.

## Provenance

| | |
|---|---|
| Upstream | https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth |
| Upstream SHA-256 / commit | `49fafd45f8fd7aa8d31ab2a22d14d91b536c34494a5cfe31eb5d89c2fa266abb` |
| Recipe | `recipes/realesrgan-x2plus.yaml` — sha256 `36c21d270546fe5fee7ad39eae6e18bbd7eaadc8d9a3faec4a270d6bb9d3abab` |
| Toolchain | Python 3.12.13, torch 2.10.0, onnx 1.23.0, onnxruntime 1.30.0 on Darwin 25.6.0 arm64 |
| Converted | 2026-09-22T18:53:36+00:00 |

## Files

| file | class | size | SHA-256 |
|---|---|---|---|
| `model.onnx` | registry | 63.97 MB | `7eb5e9eb507df603c0c04b49b23c86a362e0a01575bfbbac891d970f9c331888` |
| `model_fp16.onnx` | registry | 32.21 MB | `382dc047b478d71200ff76e9fdb920953106a8ac63380ca7370aba357c44cc5f` |

`registry` files are parameter files served from `models.skillsafe.ai` once vetted;
`bundle` files ship inside an app; `registry-shared` is a runtime library reused by
every model of the same architecture.

## Verification

ONNX Runtime (CPU) output vs the PyTorch reference on a seeded uniform input, thresholds from the recipe (`{"fp32": {"max_abs": 0.0001}, "fp16": {"max_abs": 0.05, "psnr_db": 45}}`):

| variant | input | max abs | mean abs | PSNR |
|---|---|---|---|---|
| fp32 | 64×64 | 1.85e-06 | 3.35e-07 | 127.5 dB |
| fp32 | 80×96 | 2.03e-06 | 3.39e-07 | 127.4 dB |
| fp16 | 64×64 | 6.18e-04 | 6.55e-05 | 81.5 dB |
| fp16 | 80×96 | 6.99e-04 | 7.89e-05 | 79.8 dB |

## Use in the browser

```js
import * as ort from "onnxruntime-web";
const session = await ort.InferenceSession.create("https://huggingface.co/skillsafe-ai/realesrgan-x2plus/resolve/main/model.onnx", { executionProviders: ["webgpu", "wasm"] });
const out = await session.run({ input: new ort.Tensor("float32", pixels, [1, 3, h, w]) });
```

**Contract:** input `input` float32 `['batch', 3, 'height', 'width']` → output `output` float32 `['batch', 3, 'height_x2', 'width_x2']`. Opset 17.

## Licence and attribution

Real-ESRGAN RealESRGAN_x2plus weights and RRDBNet architecture: Copyright (c) 2021, Xintao Wang. BSD 3-Clause License. https://github.com/xinntao/Real-ESRGAN

Licence: **BSD-3-Clause** — notice: https://github.com/xinntao/Real-ESRGAN/blob/a4abfb2979a7bbff3f69f58f58ae324608821e27/LICENSE. The conversion recipe and
this model card are part of the SkillSafe repository and carry its licence; the
weights remain under the upstream licence above.

The full `manifest.json` in this repo records the recipe, sources, toolchain
(including the `uv.lock` hash) and per-file verification numbers.
