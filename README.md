# Image Upscaler

**Offline AI image enhancement for Mac, with a native interface and a command-line tool.**

Enhance photos and illustrations on Apple Silicon using [MLX](https://github.com/ml-explore/mlx)
and [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN). Keep transparent edges,
soft shadows, and partial alpha intact. Your images stay on your Mac.

![Image Upscaler showing an original and enhanced RGBA sample](docs/assets/app-preview.jpg)

*Native interface with a synthetic transparency sample, enhanced locally at ×4.*

- **Local processing.** No accounts, subscriptions, activation, telemetry, or hosted inference.
- **Native macOS app.** Browse folders, compare the original and result with a draggable divider,
  zoom, and save individual enhancements.
- **×1, ×2, and ×4.** Enhance at the original size or increase resolution, with photo,
  illustration, and lightweight model presets.
- **Transparency support.** Preserve RGBA and partial alpha without adding a background.
- **Safe outputs.** Processing never replaces the original. Results are saved as separate PNGs.
- **Scriptable.** Use the same processing engine through the `upscale` command.

## Requirements

- A Mac with **Apple Silicon** (M1 or later), running **macOS 14 or later**.
- **Python 3.12–3.14** available as `python3` (or selected explicitly below).
- **Xcode Command Line Tools** for the native app. Install with `xcode-select --install`.
- Internet access for installing dependencies and explicitly downloading models.
  Once installed, image processing works offline. All four models total approximately 78 MB.

Intel Macs, Windows, and Linux are not supported. This is an early release;
see [limitations](#limitations) before choosing it for a workflow.

## Install from source

Clone the repository and run the installer:

```sh
git clone https://github.com/no-colours-fabric/image-upscaler.git
cd image-upscaler
./scripts/install.sh
```

Alternatively, use **Code → Download ZIP**, extract the archive, and run
`./scripts/install.sh` from the extracted folder.

The installer creates `~/Applications/Image Upscaler.app` and the `upscale` command.
It does not download Python or model weights. If it adds `~/.local/bin` to your shell
profile, open a new terminal before using the command.

Download the models explicitly and check the runtime:

```sh
upscale models download all
upscale doctor
```

Open **Image Upscaler** from `~/Applications`, or choose it in Finder's **Open With** menu.
Open an image or folder, choose a model and scale, click **Enhance**, then **Save**.

For command-line use only, install with `./scripts/install.sh --cli-only`.
To select a Python interpreter:

```sh
IMAGE_UPSCALER_PYTHON=/path/to/python3.12 ./scripts/install.sh
```

Normal installation copies the Python package into Application Support; the source
folder can then be moved or deleted. Keep the selected Python installation available.
The app is built and signed locally with an ad-hoc signature. No Apple developer
account is needed for this local build. A portable, signed app download is not
provided by this source installation.

## Command-line usage

```sh
upscale photo.jpg
upscale photo.jpg --scale 1
upscale photo.jpg --scale 2
upscale transparent.png --model anime
upscale photo.jpg --model fast --output result.png
```

The default is the photo preset at ×4. `photo.jpg` becomes `photo_4x.png` beside the
original. Existing CLI outputs require `--overwrite`; even that flag cannot replace
the original. Use `--quiet` to print only the output path to stdout.

```sh
upscale --help
upscale models list
upscale models verify
```

See the [user guide](docs/usage.md) for models, keyboard shortcuts, file operations,
transparency handling, and troubleshooting.

## Privacy and storage

Inference runs on the local Apple GPU. The native app starts a local Python worker;
it does not run a web server. Processing never downloads a missing model automatically.
Downloads use public model URLs without tokens, pinned to revisions and verified by SHA-256.

Models, dependencies, runtime environments, and installation caches live under
`~/Library/Application Support/image-upscaler/`, outside the repository.
Private temporary sessions hold unsaved enhancements and thumbnail caches.
See [storage and installation](docs/installation.md) for details and removal instructions.

## Limitations

- The processing pipeline uses **8-bit RGB/RGBA**. HDR, high-bit-depth workflows,
  animations, and multipage images are not supported.
- Alpha is resized with Lanczos, independently of the model. At ×1 it is copied
  unchanged. The model enhances color; it does not reconstruct the alpha mask.
- EXIF orientation is applied and the embedded ICC profile is retained. Other EXIF
  metadata is not copied. Outputs are PNG.
- Tiling limits GPU memory per pass; large output images still require RAM.
- AI enhancement can change textures, lettering, and fine details. Inspect the result
  before using it where fidelity matters.

## Development

```sh
./scripts/install.sh --dev
"$HOME/Library/Application Support/image-upscaler/runtime/env/bin/python" -m pytest -m 'not integration'
"$HOME/Library/Application Support/image-upscaler/runtime/env/bin/ruff" check .
"$HOME/Library/Application Support/image-upscaler/runtime/env/bin/ruff" format --check .
./scripts/test-native.sh
```

Development mode is editable and requires the source folder to stay in place.
GPU integration tests use locally installed models and never download weights.
See [CONTRIBUTING.md](CONTRIBUTING.md) for architecture and testing,
[verification notes](docs/verification.md) for local results, and
[CHANGELOG.md](CHANGELOG.md) for release notes.

## License and acknowledgments

Image Upscaler is licensed under [BSD-3-Clause](LICENSE). It uses existing
Real-ESRGAN models and an MLX port; it does not claim to train a new model.
Third-party components retain their own licenses, including Apache-2.0 for
BasicSR-derived code. See [THIRD_PARTY.md](THIRD_PARTY.md) and [licenses/](licenses/).

Bug reports and focused contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md)
and use [SECURITY.md](SECURITY.md) for vulnerability reports.
