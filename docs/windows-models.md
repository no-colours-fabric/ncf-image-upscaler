# Windows model sources

Windows downloads public ONNX files directly from Hugging Face. Exact repository,
immutable revision, filename, byte size and SHA-256 for all four are recorded in
`apps/windows/models.json`; the publisher's model cards and conversion manifests
are retained in `apps/windows/resources/model-cards`. They state upstream
checkpoint hashes, recipe hashes, architecture, export toolchain and licenses.
These provenance statements are attributed to the publisher; local functional
checks are separate evidence and do not independently reproduce their exporter.

| Preset / requested size | ONNX source | Native size |
| --- | --- | --- |
| Photo ×1 / ×2 | skillsafe-ai/realesrgan-x2plus | ×2 |
| Photo ×4 | skillsafe-ai/realesrgan-x4plus | ×4 |
| Illustration ×1 / ×2 / ×4 | skillsafe-ai/realesrgan-x4plus-anime-6b | ×4 |
| Fast ×1 / ×2 / ×4 | skillsafe-ai/realesr-general-x4v3 | ×4 |

All selected variants are FP32, NCHW RGB `[0,1]`, opset 17 with input named
`input`. Scale reductions happen after neural inference in the shared imaging
pipeline. Alpha is resized separately, never inferred or flattened.

The three RRDB graphs are upstream FP32 conversions. They replace the earlier
local Windows research route that promoted pinned MLX FP16 tensors to FP32;
promotion did not restore upstream FP32 precision. Fast's publisher declares the
same upstream `.pth` SHA used by earlier research, but its ONNX graph/hash is
different. Old 63-case and FullHD results are not evidence for these new graphs.
There is no claim of MLX numerical parity or identical output pixels.

Upstream Real-ESRGAN weights are BSD-3-Clause, Copyright (c) 2021 Xintao Wang;
the notice accompanies the application. BasicSR attribution/Apache notices in
the repository are also retained. The ONNX publishers retain their authorship;
NCF does not claim to have trained or authored these conversions.

Models are never in source Git, Windows installers or GitHub release assets.
An explicit user action prepares the cache, checks both length/hash and publishes
atomically. Bad downloads cannot become ready. Missing/corrupted models show an
actionable message; Enhance does not make network requests. Downloaded caches are
kept on uninstall to avoid forcing another download, and may be removed manually
after closing all application windows.
