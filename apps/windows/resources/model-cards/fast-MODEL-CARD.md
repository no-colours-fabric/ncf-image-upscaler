---
license: bsd-3-clause
tags:
  - skillsafe
  - browser
  - onnxruntime-web
  - image-super-resolution
  - onnx
---

# Real-ESRGAN general x4 v3 (SRVGGNetCompact)

Browser-ready `onnx` artifacts for **image-super-resolution**, produced by SkillSafe's
reproducible converter ([`models/` in skillsafe.ai](https://github.com/skillsafe-admin/skillsafe.ai-website/tree/main/models))
from a pinned upstream source. Every byte here is derivable from that source plus
the recipe below; nothing was edited by hand.

## Provenance

| | |
|---|---|
| Upstream | https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-general-x4v3.pth |
| Upstream SHA-256 / commit | `8dc7edb9ac80ccdc30c3a5dca6616509367f05fbc184ad95b731f05bece96292` |
| Recipe | `recipes/realesr-general-x4v3.yaml` — sha256 `bc93d30609e3b981c4c61bec23b2c8df737241e9ed64aa99879b21949579fc4f` |
| Toolchain | Python 3.12.13, torch 2.10.0, onnx 1.23.0, onnxruntime 1.30.0 on Darwin 25.6.0 arm64 |
| Converted | 2026-09-22T03:08:55+00:00 |

## Files

| file | class | size | SHA-256 |
|---|---|---|---|
| `model.onnx` | registry | 4.64 MB | `a946f7a9397021b9b6b7e71df3d2821b04cc09ff244423b7ca79cb191ce4a00e` |
| `model_fp16.onnx` | registry | 2.33 MB | `8dedfc4b8916f2426111561351bbd3c35d674214a3f5bc28190084cd15133a67` |

`registry` files are parameter files served from `models.skillsafe.ai` once vetted;
`bundle` files ship inside an app; `registry-shared` is a runtime library reused by
every model of the same architecture.

## Verification

ONNX Runtime (CPU) output vs the PyTorch reference on a seeded uniform input, thresholds from the recipe (`{"fp32": {"max_abs": 0.0001}, "fp16": {"max_abs": 0.05, "psnr_db": 45}}`):

| variant | input | max abs | mean abs | PSNR |
|---|---|---|---|---|
| fp32 | 64×64 | 4.41e-06 | 4.91e-07 | 123.8 dB |
| fp32 | 80×96 | 4.11e-06 | 4.99e-07 | 123.7 dB |
| fp16 | 64×64 | 1.82e-03 | 2.81e-04 | 68.6 dB |
| fp16 | 80×96 | 1.78e-03 | 2.77e-04 | 68.8 dB |

## Use in the browser

```js
import * as ort from "onnxruntime-web";
const session = await ort.InferenceSession.create("https://huggingface.co/skillsafe-ai/realesr-general-x4v3/resolve/main/model.onnx", { executionProviders: ["webgpu", "wasm"] });
const out = await session.run({ input: new ort.Tensor("float32", pixels, [1, 3, h, w]) });
```

**Contract:** input `input` float32 `['batch', 3, 'height', 'width']` → output `output` float32 `['batch', 3, 'height_x4', 'width_x4']`. Opset 17.

## Licence and attribution

Real-ESRGAN realesr-general-x4v3 weights and SRVGGNetCompact architecture: Copyright (c) 2021, Xintao Wang. BSD 3-Clause License. https://github.com/xinntao/Real-ESRGAN

Licence: **BSD-3-Clause** — notice: https://github.com/xinntao/Real-ESRGAN/blob/a4abfb2979a7bbff3f69f58f58ae324608821e27/LICENSE. The conversion recipe and
this model card are part of the SkillSafe repository and carry its licence; the
weights remain under the upstream licence above.

The full `manifest.json` in this repo records the recipe, sources, toolchain
(including the `uv.lock` hash) and per-file verification numbers.
