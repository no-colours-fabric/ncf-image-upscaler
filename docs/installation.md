# Installation and storage

## Standalone DMG

Download the Apple Silicon DMG from [Releases](https://github.com/no-colours-fabric/ncf-image-upscaler/releases).
Drag the app into Applications and open it. No system Python or Xcode is needed.
This build is not notarized by Apple; follow the first-launch instructions in the README
and the included `INSTALL.txt` only if you trust the release and have checked its checksum.

### Verify a download

Download both the DMG and `SHA256SUMS.txt` from the **same release** into the same folder.
Open Terminal in that folder and run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

The result should show `NCFImageUpscaler-0.4.0-arm64.dmg: OK` for version 0.4.0.
If it reports a mismatch, do not install that file; download both files again from
the [official releases](https://github.com/no-colours-fabric/ncf-image-upscaler/releases).
The checksum checks that the file matches the published download; it is not Apple notarization.

### First launch

The first launch verifies and extracts the bundled engine without accessing the network.
The versioned engine is installed under `runtime/portable/PAYLOAD_SHA256/` in the data
directory. It is independent of the source installer's `runtime/env/` and will not replace it.
Models are shared between both installations. Old portable engines remain available for
older app versions; you can remove unused version folders after closing those versions.

Choose **Download Models** in the setup window to download the missing models explicitly.
Use **NCF Image Upscaler → Models…** to check, retry, or cancel. Successfully verified models
are reused; failed or cancelled downloads are not published as installed weights.
An enhancement request never initiates a download.

The DMG app uses the current user's Application Support directory, without a path from
the build machine. Copying or moving the app does not change its installed engine location.
It does not create a command in `PATH` or modify shell settings.

### Update the DMG app

Check [the latest release](https://github.com/no-colours-fabric/ncf-image-upscaler/releases/latest),
download its DMG and checksum, and verify the download. Save your results and quit
NCF Image Upscaler before replacing the app in Applications with the new copy.
Downloaded models remain in Application Support and are reused when their pinned
versions match. A new engine payload is installed locally on the next launch.
The source checkout is not needed for installation or updates.

### Upgrade from Image Upscaler 0.3.x

Version 0.4.0 is named **NCF Image Upscaler**. Install `NCF Image Upscaler.app`,
open it, and let it finish checking models before removing the old app.
The new version copies matching, checksum-verified models from
`~/Library/Application Support/image-upscaler/models/` into
`~/Library/Application Support/ncf-image-upscaler/models/` without a download.
Existing files in the new model directory are never overwritten during migration.
The old installation is left intact. Sidebar settings are imported once on first launch.
Custom data directories selected with `NCF_IMAGE_UPSCALER_HOME` stay isolated and
do not automatically import models from an older installation.

Source users should run the installer again and use **`ncf-upscale`**.
The Python module is now `ncf_image_upscaler`, and environment overrides are
`NCF_IMAGE_UPSCALER_HOME` and `NCF_IMAGE_UPSCALER_PYTHON`.
After verifying the new installation, remove the old app and the old `upscale`
symlink only if it belongs to this project. The old data directory can then be
removed separately once it is no longer needed by an older version.

## Install or update from source

Use a source download or clone, open Terminal in its root, and run
`./scripts/install.sh`. Re-running the installer updates the installed Python
package and rebuilds the native app. It keeps downloaded models.
The installer validates macOS/arm64 and Python 3.12–3.14 before installing.

For the CLI alone, pass `--cli-only`. For an editable development environment,
pass `--dev` (or combine `--dev --cli-only`). Normal installation uses a regular
package installation and does not require the checkout after installation.
Keep the selected Python interpreter installed: the virtual environment uses it.

The installer pins uv and resolves project dependencies from `uv.lock` with
`--locked`. It does not upgrade or modify the system Python. Build dependencies
and downloaded packages use the uv cache below. Model downloads are a separate,
explicit step: `ncf-upscale models download all`.

## Files created

```text
~/Library/Application Support/ncf-image-upscaler/
├── runtime/
│   ├── tooling/         # uv installation tooling
│   ├── env/             # installed package, dependencies, and CLI entry point
│   ├── native-build/    # local app and native test builds
│   └── portable/        # DMG engines, one directory per payload SHA-256
├── models/              # model ID / pinned revision / model.safetensors
└── cache/uv/            # installation cache

/Applications/NCF Image Upscaler.app   # usual DMG destination
~/Applications/NCF Image Upscaler.app  # source installer destination
~/.local/bin/ncf-upscale               # source installation's CLI symlink
```

A DMG installation uses the portable engine and shared model folders. The source
installer also creates `tooling/`, `env/`, `native-build/` (for the native app),
and the CLI symlink. You can keep the DMG app in another folder if you prefer.

The source installer registers the app with Finder, without changing default file
associations. It refuses to replace an unrelated app or CLI command.
If `~/.local/bin` is absent from `PATH`, it appends a marked block to `~/.zprofile`
(or `~/.bash_profile` for Bash). Zsh's `ZDOTDIR` is respected. Existing settings
are preserved; repeated installation does not duplicate the block.

Each window owns a private temporary session for results and thumbnails.
Thumbnail RAM and disk caches are reused during the session and removed when it
closes. Abandoned sessions are cleaned up on a later launch. These are temporary
files, not installation caches or model weights.

## Custom paths

Set `NCF_IMAGE_UPSCALER_PYTHON` when installing to choose an interpreter.
Set `NCF_IMAGE_UPSCALER_HOME` to change the data directory. For CLI use, keep that
variable set when running `ncf-upscale`. The locally built app remembers its data
directory and passes it to the worker.

To rebuild only the native app, use `./scripts/build-app.sh --install`.
This does not update the installed Python package. After Python changes,
reinstall or use editable development mode.

## Troubleshooting

- **The DMG app is blocked on its first launch:** follow the
  [README's first-launch instructions](../README.md#download-for-mac). This release
  is not notarized. Do not override a malware or damaged-app warning.
- **Model setup failed or was cancelled:** open **NCF Image Upscaler → Models…** and
  choose **Download Models** to retry. Verified installed models are kept. When all
  models are ready, **Verify Again** checks them without downloading.
- **`python3` is missing or unsupported:** install Python 3.12–3.14 separately,
  then select it with `NCF_IMAGE_UPSCALER_PYTHON` for a source installation. The DMG
  already includes Python.
- **Swift compiler is missing during a source installation:** install Xcode Command
  Line Tools, or use `--cli-only`. The DMG does not require a compiler.
- **`ncf-upscale` is not found:** open a new terminal and check that `~/.local/bin` is
  in `PATH`. The installed command can also be run by its full path.
- **A model is missing or corrupted:** run `ncf-upscale models download MODEL_ID`,
  then `ncf-upscale models verify`. Processing does not fall back to a network download.
- **GPU initialization fails:** use a native arm64 terminal session on an Apple
  Silicon Mac and run `ncf-upscale doctor`. A remote or restricted environment may
  not expose the GPU.
- **Memory pressure:** try a smaller even tile size, such as `--tile 128`.
  Final output assembly still needs memory proportional to output size.

## Remove the installation

Save any results you want to keep and quit the app. Delete the app from
`/Applications` for a typical DMG installation, `~/Applications` for a source
installation, or the folder where you placed it. If you installed the CLI, remove
`~/.local/bin/ncf-upscale` **only if it is this project's symlink**.

Delete `~/Library/Application Support/ncf-image-upscaler` to remove the
runtime, models, and installation caches. For a custom installation, remove its
selected data directory instead. This data is shared by DMG and source installations;
keep it if you still use either installation.

For a source installation, remove only the block between `# >>> ncf-image-upscaler PATH >>>` and
`# <<< ncf-image-upscaler PATH <<<` from the shell profile if it is no longer wanted.
The source folder is independent and may be kept or deleted. Saved output images
are not removed by any of these steps.
