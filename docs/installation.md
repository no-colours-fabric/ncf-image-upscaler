# Installation and storage

## Install or update

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
explicit step: `upscale models download all`.

## Files created

```text
~/Library/Application Support/image-upscaler/
├── runtime/
│   ├── tooling/         # uv installation tooling
│   ├── env/             # installed package, dependencies, and CLI entry point
│   └── native-build/    # local app and native test builds
├── models/              # model ID / pinned revision / model.safetensors
└── cache/uv/            # installation cache

~/Applications/Image Upscaler.app
~/.local/bin/upscale     # symlink to the installed CLI entry point
```

The installer registers the app with Finder, without changing default file
associations. It refuses to replace an unrelated app or CLI command.
If `~/.local/bin` is absent from `PATH`, it appends a marked block to `~/.zprofile`
(or `~/.bash_profile` for Bash). Zsh's `ZDOTDIR` is respected. Existing settings
are preserved; repeated installation does not duplicate the block.

Each window owns a private temporary session for results and thumbnails.
Thumbnail RAM and disk caches are reused during the session and removed when it
closes. Abandoned sessions are cleaned up on a later launch. These are temporary
files, not installation caches or model weights.

## Custom paths

Set `IMAGE_UPSCALER_PYTHON` when installing to choose an interpreter.
Set `IMAGE_UPSCALER_HOME` to change the data directory. For CLI use, keep that
variable set when running `upscale`. The locally built app remembers its data
directory and passes it to the worker.

To rebuild only the native app, use `./scripts/build-app.sh --install`.
This does not update the installed Python package. After Python changes,
reinstall or use editable development mode.

## Troubleshooting

- **`python3` is missing or unsupported:** install Python 3.12–3.14 separately,
  then select it with `IMAGE_UPSCALER_PYTHON`.
- **Swift compiler is missing:** install Xcode Command Line Tools, or use `--cli-only`.
- **`upscale` is not found:** open a new terminal and check that `~/.local/bin` is
  in `PATH`. The installed command can also be run by its full path.
- **A model is missing or corrupted:** run `upscale models download MODEL_ID`,
  then `upscale models verify`. Processing does not fall back to a network download.
- **GPU initialization fails:** use a native arm64 terminal session on an Apple
  Silicon Mac and run `upscale doctor`. A remote or restricted environment may
  not expose the GPU.
- **Memory pressure:** try a smaller even tile size, such as `--tile 128`.
  Final output assembly still needs memory proportional to output size.

## Remove the installation

Quit the app and save any results you want to keep. Delete the app from
`~/Applications`, then remove `~/.local/bin/upscale` **only if it is this project's
symlink**. Delete `~/Library/Application Support/image-upscaler` to remove the
runtime, models, and installation caches. For a custom installation, remove its
selected data directory instead.

Remove only the block between `# >>> image-upscaler PATH >>>` and
`# <<< image-upscaler PATH <<<` from the shell profile if it is no longer wanted.
The source folder is independent and may be kept or deleted. Saved output images
are not removed by any of these steps.
