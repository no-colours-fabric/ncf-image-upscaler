---
license: bsd-3-clause
tags:
  - skillsafe
  - browser
  - onnxruntime-web
  - image-super-resolution
  - onnx
---

# Real-ESRGAN x4plus anime 6B (RRDBNet 6 blocks)

Browser-ready `onnx` artifacts for **image-super-resolution**, produced by SkillSafe's
reproducible converter ([`models/` in skillsafe.ai](https://github.com/skillsafe-admin/skillsafe.ai-website/tree/main/models))
from a pinned upstream source. Every byte here is derivable from that source plus
the recipe below; nothing was edited by hand.

## Provenance

| | |
|---|---|
| Upstream | https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth |
| Upstream SHA-256 / commit | `f872d837d3c90ed2e05227bed711af5671a6fd1c9f7d7e91c911a61f155e99da` |
| Recipe | `recipes/realesrgan-x4plus-anime-6b.yaml` — sha256 `56cb0c56f6231351a9dc4b16e62e2db686ed74a31b8b18ba20c90e830add5802` |
| Toolchain | Python 3.12.13, torch 2.10.0, onnx 1.23.0, onnxruntime 1.30.0 on Darwin 25.6.0 arm64 |
| Converted | 2026-09-22T03:08:57+00:00 |

## Files

| file | class | size | SHA-256 |
|---|---|---|---|
| `model.onnx` | registry | 17.11 MB | `9a029dae374b2cd4c3eb2dbbed857e22e6d785687c767aa12828e7356b9fb378` |
| `model_fp16.onnx` | registry | 8.61 MB | `1777c7dffecdf356c234e3387d456a196ed9b72f9f14ed96bc097b9798b7ddbf` |

`registry` files are parameter files served from `models.skillsafe.ai` once vetted;
`bundle` files ship inside an app; `registry-shared` is a runtime library reused by
every model of the same architecture.

## Verification

ONNX Runtime (CPU) output vs the PyTorch reference on a seeded uniform input, thresholds from the recipe (`{"fp32": {"max_abs": 0.0001}, "fp16": {"max_abs": 0.05, "psnr_db": 45}}`):

| variant | input | max abs | mean abs | PSNR |
|---|---|---|---|---|
| fp32 | 64×64 | 3.34e-06 | 4.41e-07 | 125.0 dB |
| fp32 | 80×96 | 2.98e-06 | 4.28e-07 | 125.3 dB |
| fp16 | 64×64 | 7.19e-04 | 1.67e-04 | 73.6 dB |
| fp16 | 80×96 | 1.03e-03 | 1.49e-04 | 74.2 dB |

## Use in the browser

```js
import * as ort from "onnxruntime-web";
const session = await ort.InferenceSession.create("https://huggingface.co/skillsafe-ai/realesrgan-x4plus-anime-6b/resolve/main/model.onnx", { executionProviders: ["webgpu", "wasm"] });
const out = await session.run({ input: new ort.Tensor("float32", pixels, [1, 3, h, w]) });
```

**Contract:** input `input` float32 `['batch', 3, 'height', 'width']` → output `output` float32 `['batch', 3, 'height_x4', 'width_x4']`. Opset 17.

## Licence and attribution

Real-ESRGAN RealESRGAN_x4plus_anime_6B weights and RRDBNet architecture: Copyright (c) 2021, Xintao Wang. BSD 3-Clause License. https://github.com/xinntao/Real-ESRGAN

Licence: **BSD-3-Clause** — notice: https://github.com/xinntao/Real-ESRGAN/blob/a4abfb2979a7bbff3f69f58f58ae324608821e27/LICENSE. The conversion recipe and
this model card are part of the SkillSafe repository and carry its licence; the
weights remain under the upstream licence above.

The full `manifest.json` in this repo records the recipe, sources, toolchain
(including the `uv.lock` hash) and per-file verification numbers.
