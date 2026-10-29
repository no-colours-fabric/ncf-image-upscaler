# Contributing to Image Upscaler

Bug reports, documentation improvements, and focused pull requests are welcome.
Use English for discussions, documentation, interface text, and diagnostics.
Be respectful, describe observable behavior, and do not post private images or
personal information without permission.

For substantial features, open an issue first so scope and maintenance can be
discussed. The project targets macOS on Apple Silicon and keeps normal processing
offline, free, and independent of accounts or hosted services.

## Development setup

Install Python 3.12–3.14 and Xcode Command Line Tools, then run from the project root:

```sh
./scripts/install.sh --dev
```

This creates an editable environment under Application Support, outside Git.
Keep the checkout in place. Re-run the installer after changing dependencies.
Use `--cli-only` if you do not need the installed app.

```sh
APP_HOME="$HOME/Library/Application Support/image-upscaler"
"$APP_HOME/runtime/env/bin/python" -m pytest -m 'not integration'
"$APP_HOME/runtime/env/bin/ruff" check .
"$APP_HOME/runtime/env/bin/ruff" format --check .
./scripts/test-native.sh
./scripts/build-app.sh
```

`APP_HOME` above is a shell variable, not a runtime override. Use
`IMAGE_UPSCALER_HOME` consistently for an isolated installation.

## GPU integration checks

Download models explicitly during setup, then run the integration tests offline:

```sh
upscale models download all
upscale models verify
"$HOME/Library/Application Support/image-upscaler/runtime/env/bin/python" -m pytest -m integration
```

Tests never download weights. Missing weights skip the corresponding GPU tests;
a skipped test is not evidence of a successful GPU pass. The native suite also
runs real worker and cancellation checks when a runtime and ×2 model are available.
Standard CI runs unit and native checks without weights, builds the distributions,
and checks that a non-editable source installation works after source removal. Actual GPU validation
must be recorded separately on a Mac that exposes Metal.

## Architecture

| Component | Responsibility |
| --- | --- |
| `imaging.py` | Public `upscale_image()` API, image formats, alpha, safe PNG output |
| `engine.py` | Local MLX adapter and tiled inference |
| `models.py` / `models.json` | Pinned artifacts, integrity checks, explicit downloads |
| `cli.py` | Command-line adapter |
| `worker.py` | JSON Lines bridge used by the native app |
| `native/Sources/` | Swift/AppKit interface and file operations |
| `_vendor/` | Pinned upstream model architectures and tiling helpers |

Keep the processing API and MLX engine independent of both interfaces. Preserve
partial alpha, colored edges on light and dark backgrounds, and the prohibition
on replacing inputs. Add meaningful regression coverage for behavior changes.
Keep model weights, environments, and caches outside Git.

Do not reformat vendored code. Preserve its notices, update `THIRD_PARTY.md` when
changing it, and record its source revision. Dependency changes must update
`uv.lock`; model changes must pin revisions, sizes, and SHA-256 hashes.

## Pull requests

Explain the problem, the resulting behavior, and relevant validation. Include
screenshots for interface changes and mention checks you could not run.
Keep unrelated changes separate. Contributions are accepted under the project's
BSD-3-Clause license; third-party components retain their existing licenses.
See [SECURITY.md](SECURITY.md) for private vulnerability reporting.

## Binary packaging

See [binary-release.md](docs/binary-release.md) for the standalone DMG builder,
pinned Python provenance, license packaging, and relocation/GPU verification.
Model setup is an explicit adapter in `setup_models.py`; inference stays offline.
