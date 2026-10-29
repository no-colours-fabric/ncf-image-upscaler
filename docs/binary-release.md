# Standalone binary releases

The DMG targets Apple Silicon and macOS 14 or later. It is locally ad-hoc signed
and **not notarized by Apple**. It requires no separate Python, Xcode, account,
subscription, activation, or server. See the README and `packaging/INSTALL.txt`
for first-launch instructions.

## Layout and first launch

The app carries `runtime.tar`, a complete prepared Python environment, plus
`portable-runtime.json` with its SHA-256. First launch verifies and extracts that
payload into:

```text
~/Library/Application Support/image-upscaler/runtime/portable/PAYLOAD_SHA256/
```

Installation uses a cross-process file lock, a private staging directory, and an
atomic directory move. It does not download anything or alter the source
installation's `runtime/env/`. Different payload versions use separate directories.
The interpreter and entry points resolve their location after moving the app or
runtime. Python workers use isolated mode and ignore external Python settings.

The native Models window starts downloads only after **Download Models** is
chosen. Installed weights are checked against the pinned model manifest. Cancelled
or failed downloads are not published as model files. Inference never downloads a
model automatically. The standalone runtime contains certifi's CA bundle for HTTPS.

## Build locally

Install the development environment, then run:

```sh
APP_HOME="$HOME/Library/Application Support/image-upscaler"
"$APP_HOME/runtime/env/bin/python" scripts/build-dmg.py
"$APP_HOME/runtime/env/bin/python" scripts/check-binary.py "$APP_HOME"/runtime/releases/0.3.0/*.dmg
```

This is an explicit build/installation command: it may download the pinned Python
archives and locked dependency wheels. All downloads, environments, and build
artifacts remain under Application Support. The shipped runtime excludes development
dependencies and model weights. Do not commit the resulting app, DMG, or runtime.

`packaging/python-runtime.json` pins the interpreter and the corresponding full
archive used for component notices by URL, size, and SHA-256. Python distributions
come from Astral's python-build-standalone. Dependency wheels are selected for
macOS 14 arm64, with hashes exported from `uv.lock`; compilation from dependency
source distributions is disabled. The builder checks Mach-O deployment targets,
external library links, and symlinks before applying local signatures.

The app includes complete installed dependency notices under
`Contents/Resources/Licenses/Runtime`, together with Python provenance and applicable
component licenses. See `THIRD_PARTY.md` for packaging changes and the documented
system-zlib metadata discrepancy in the upstream Python archive.

## Verification

`check-binary.py` mounts the DMG read-only, copies its app into a path containing
spaces, verifies its signature and payload, and bootstraps a fresh isolated runtime.
It restricts `PATH`, supplies invalid `PYTHONHOME`/`PYTHONPATH` and `DEVELOPER_DIR`,
then removes the copied app to check runtime independence. It checks imports,
HTTPS roots, model status, the CLI, preservation of the input, and safe failure
without a missing-model download.

On a Mac with Metal and already verified local weights, add `--gpu` to test all
four models and ×1 modes through the packaged interpreter. These checks deny Python
network connections and verify exact alpha, unchanged inputs, and compositing on
light and dark backgrounds. They do not download weights.

This isolation is not a claim that a separate physical Mac was used. Hosted CI
also tests the actual generated DMG on macOS 15; local GPU and interface checks
are recorded in `docs/verification.md`.

## Publish

1. Keep versions consistent and run the source checks in `CONTRIBUTING.md`.
2. Build and verify the DMG locally, including GPU and interface checks.
3. Push the source commit and wait for CI to pass.
4. Push the matching version tag, such as `v0.3.0`.

The tag-triggered **Binary release** workflow builds a fresh DMG on macOS 15,
verifies a relocated installation without models or system Python, and only then
creates and publishes a GitHub Release with the DMG, `SHA256SUMS.txt`, and
`packaging/RELEASE_NOTES.md`. Its GitHub token has content-write permission only
in that release job. No Apple certificate or signing credentials are required.
