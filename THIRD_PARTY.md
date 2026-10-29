# Third-party sources and model provenance

Image Upscaler's original code is BSD-3-Clause. Included third-party code keeps
its own terms. The Python distribution declares `BSD-3-Clause AND Apache-2.0`
to account for the BasicSR-derived architecture in the MLX port.

## Real-ESRGAN MLX port

Vendored directory: `src/image_upscaler/_vendor/realesrgan_mlx`.

- Source: <https://github.com/xocialize/realesrgan-mlx>
- Revision: `52c0fc1044277900b995308095a1f3cc484a3581`.
- Attribution: MVS Collective (xocialize), as identified in upstream package metadata.
- License declared in the pinned README and `pyproject.toml`: BSD-3-Clause.
- Upstream has no standalone LICENSE file at that revision. Its explicit license
  declaration is recorded here, together with its attribution. The underlying
  Real-ESRGAN license is included in `licenses/Real-ESRGAN-BSD-3-Clause.txt`.
- Source declarations checked on 2026-10-29:
  [README](https://github.com/xocialize/realesrgan-mlx/blob/52c0fc1044277900b995308095a1f3cc484a3581/README.md),
  [package metadata](https://github.com/xocialize/realesrgan-mlx/blob/52c0fc1044277900b995308095a1f3cc484a3581/pyproject.toml).

Included: RRDBNet and SRVGGNetCompact architectures, NHWC spatial operations,
and tiled inference. The five implementation files and `archs/__init__.py` were
compared byte-for-byte with the pinned upstream source on 2026-10-29 and match.
Upstream's downloader, CLI, model configuration, conversion scripts, and
development tools are excluded.

### Local changes to the vendored package

- `__init__.py`: replaced upstream configuration imports and exports with a
  descriptive module docstring; the configuration module is not vendored.
- `utils/__init__.py`: removed eager re-exports; modules are imported directly.
- No local changes to the architecture, spatial, or tiling implementation files.

Our separate `engine.py` adapter uses fp16 and reports tile completion. Our image
pipeline handles file formats, transparency, and output saving independently.

## BasicSR-derived architecture

The MLX port identifies its RRDBNet architecture as a translation of
`basicsr/archs/rrdbnet_arch.py`, with PyTorch operations translated to MLX and
NCHW tensors translated to NHWC. Its spatial helpers also translate operations
used by that architecture. The original implementation is credited here in
addition to the immediate port.

- Source: <https://github.com/XPixelGroup/BasicSR>
- Reference release: `v1.4.2` (the minimum version named by the MLX port's parity dependencies).
  This reference documents the source and license; the port does not identify
  an exact BasicSR source commit from which it was translated.
- Copyright 2018–2022 BasicSR Authors.
- License: Apache-2.0, copied verbatim from that release into
  `licenses/BasicSR-Apache-2.0.txt`.
- [Architecture](https://github.com/XPixelGroup/BasicSR/blob/v1.4.2/basicsr/archs/rrdbnet_arch.py),
  [license](https://github.com/XPixelGroup/BasicSR/blob/v1.4.2/LICENSE.txt), and
  [component acknowledgments](https://github.com/XPixelGroup/BasicSR/blob/v1.4.2/LICENSE/README.md).

BasicSR itself and its unrelated model architectures are not bundled or installed.
The MLX source docstrings identify the translation; Image Upscaler retains them.

## Original Real-ESRGAN

- Source: <https://github.com/xinntao/Real-ESRGAN>
- Copyright (c) 2021, Xintao Wang.
- License: BSD-3-Clause, reproduced in `licenses/Real-ESRGAN-BSD-3-Clause.txt`.
- Paper: Wang et al., *Real-ESRGAN: Training Real-World Blind Super-Resolution
  with Pure Synthetic Data* (2021), <https://arxiv.org/abs/2107.10833>.

The compact SRVGG architecture and tiled inference are MLX translations of
Real-ESRGAN implementations, as identified in their retained source docstrings.

## Downloaded models

Weights are not included in the repository or source/Python distributions.
`src/image_upscaler/models.json` pins the repository revision, byte size, and
SHA-256 of each fp16 MLX conversion published by mlx-community.

| Model ID | Model card at the pinned revision |
| --- | --- |
| `x4plus` | [Real-ESRGAN-x4plus](https://huggingface.co/mlx-community/Real-ESRGAN-x4plus/blob/16c284e716eeec6a5634154c813b9148d35e8ea8/README.md) |
| `x2plus` | [Real-ESRGAN-x2plus](https://huggingface.co/mlx-community/Real-ESRGAN-x2plus/blob/c42bece4e3bfcd84a9a264dee0145fea637e5775/README.md) |
| `anime` | [Real-ESRGAN-x4plus-anime-6B](https://huggingface.co/mlx-community/Real-ESRGAN-x4plus-anime-6B/blob/5fa0cb713afb4daa2c4146c615f10cec886a8759/README.md) |
| `fast` | [Real-ESRGAN-general-x4v3](https://huggingface.co/mlx-community/Real-ESRGAN-general-x4v3/blob/e9a382fa779f227abf65ad49d4e5b90c1202d683/README.md) |

All four pinned model cards were checked on 2026-10-29. They declare
BSD-3-Clause and identify conversions of official Real-ESRGAN checkpoints.
They retain their upstream authorship; Image Upscaler does not train these models.
The Fast preset uses `model.safetensors` directly, without the upstream optional
denoise-weight blend.

## Runtime dependencies

Installed separately, with versions and distribution hashes in `uv.lock`:

- Apple MLX / mlx-metal — MIT.
- NumPy — BSD-3-Clause.
- Pillow — MIT-CMU.
- SciPy — BSD-3-Clause; bundled components have their own notices.
- certifi — MPL-2.0; the Mozilla CA bundle is supplied as source data.

The installed distributions retain their license files. Development and
installation tools retain their respective distribution licenses. Source-built apps use that separately installed environment. The standalone DMG
redistributes a prepared runtime payload, including those distributions and their
complete installed license notices. The active environment is extracted to Application Support.

## Packaging

The Python wheel and source archive include this file and the license texts.
The locally built app includes them in `Contents/Resources/Licenses`.
The standalone DMG includes `Contents/Resources/Licenses/Runtime/` with each
installed distribution's license files and metadata, the CPython license, and
the complete component-license references from the pinned full Python build.
`bundled-distributions.json` lists the distributions actually shipped.

## Standalone Python distribution

The binary build uses Astral's python-build-standalone CPython 3.12.15 for
aarch64-apple-darwin, release `20261013`, install-only stripped archive.
The archive URL, size, SHA-256, and the corresponding full archive used for
component licenses are pinned in `packaging/python-runtime.json`. CPython uses
PSF-2.0/Python-2.0 terms; its built-in libraries retain their respective terms.
The full build's `PYTHON.json` and all applicable component-license files are included.
The upstream macOS metadata mentions a missing zlib-ng notice, although this
interpreter links Apple's system `libz` and does not ship zlib-ng. The binary
checks that linkage and includes `SYSTEM-LIBRARY-NOTES.txt` documenting the
upstream metadata discrepancy; the provided zlib notice is retained.
Source: <https://github.com/astral-sh/python-build-standalone/releases/tag/20261013>.

Packaging rewrites Python entry-point launchers to use the interpreter beside
them, removes build-machine `direct_url.json` metadata and bytecode caches,
applies local ad-hoc signatures to Mach-O files, and refreshes distribution
RECORD hashes after these packaging changes. It does not change model algorithms
or third-party Python module implementations. All original notices are retained.
Dependency wheels are selected for macOS 14 arm64, and native deployment targets
are checked before packaging. No downloaded model weights are included.

Release-only tooling (including zstandard) is pinned in the development group of
`uv.lock` and is not added to the runtime payload. The full Python build is used
only for license metadata; the shipped interpreter comes from the stripped archive.
