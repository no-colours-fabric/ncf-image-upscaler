---
license: bsd-3-clause
tags:
  - skillsafe
  - browser
  - onnxruntime-web
  - image-super-resolution
  - onnx
---

# Real-ESRGAN x4plus (RRDBNet 23 blocks)

Browser-ready `onnx` artifacts for **image-super-resolution**, produced by SkillSafe's
reproducible converter ([`models/` in skillsafe.ai](https://github.com/skillsafe-admin/skillsafe.ai-website/tree/main/models))
from a pinned upstream source. Every byte here is derivable from that source plus
the recipe below; nothing was edited by hand.

## Provenance

| | |
|---|---|
| Upstream | https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth |
| Upstream SHA-256 / commit | `4fa0d38905f75ac06eb49a7951b426670021be3018265fd191d2125df9d682f1` |
| Recipe | `recipes/realesrgan-x4plus.yaml` — sha256 `d9c7db59a4d24f1d6e3ec90a827c1b544e2c99ef0195773d3a5739d0c15bc109` |
| Toolchain | Python 3.12.13, torch 2.10.0, onnx 1.23.0, onnxruntime 1.30.0 on Darwin 25.6.0 arm64 |
| Converted | 2026-09-22T03:09:04+00:00 |

## Files

| file | class | size | SHA-256 |
|---|---|---|---|
| `model.onnx` | registry | 63.95 MB | `4851ec156207d271f5328605d0582eeb851e656227da8aca093ced9e60789291` |
| `model_fp16.onnx` | registry | 32.19 MB | `38fe853c9cd8e1d6fd0ff387f2d43c51c1352feb9d7b3e2533d4c07b1b932f68` |

`registry` files are parameter files served from `models.skillsafe.ai` once vetted;
`bundle` files ship inside an app; `registry-shared` is a runtime library reused by
every model of the same architecture.

## Verification

ONNX Runtime (CPU) output vs the PyTorch reference on a seeded uniform input, thresholds from the recipe (`{"fp32": {"max_abs": 0.0001}, "fp16": {"max_abs": 0.05, "psnr_db": 45}}`):

| variant | input | max abs | mean abs | PSNR |
|---|---|---|---|---|
| fp32 | 64×64 | 2.26e-06 | 3.07e-07 | 128.1 dB |
| fp32 | 80×96 | 2.32e-06 | 3.00e-07 | 128.3 dB |
| fp16 | 64×64 | 1.96e-03 | 1.92e-04 | 72.8 dB |
| fp16 | 80×96 | 1.13e-03 | 1.96e-04 | 72.7 dB |

## Use in the browser

```js
import * as ort from "onnxruntime-web";
const session = await ort.InferenceSession.create("https://huggingface.co/skillsafe-ai/realesrgan-x4plus/resolve/main/model.onnx", { executionProviders: ["webgpu", "wasm"] });
const out = await session.run({ input: new ort.Tensor("float32", pixels, [1, 3, h, w]) });
```

**Contract:** input `input` float32 `['batch', 3, 'height', 'width']` → output `output` float32 `['batch', 3, 'height_x4', 'width_x4']`. Opset 17.

## Licence and attribution

Real-ESRGAN RealESRGAN_x4plus weights and RRDBNet architecture: Copyright (c) 2021, Xintao Wang. BSD 3-Clause License. https://github.com/xinntao/Real-ESRGAN

Licence: **BSD-3-Clause** — notice: https://github.com/xinntao/Real-ESRGAN/blob/a4abfb2979a7bbff3f69f58f58ae324608821e27/LICENSE. The conversion recipe and
this model card are part of the SkillSafe repository and carry its licence; the
weights remain under the upstream licence above.

The full `manifest.json` in this repo records the recipe, sources, toolchain
(including the `uv.lock` hash) and per-file verification numbers.
