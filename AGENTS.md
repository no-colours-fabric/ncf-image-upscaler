# NCF Image Upscaler

- This repository contains the native macOS app/CLI for Apple Silicon and an
  independently versioned experimental Windows CPU app in `apps/windows`.
  Follow `docs/architecture/platforms.md` and platform-scoped instructions.
- Use English for the interface, documentation, diagnostics, and contributions.
  Keep Unicode filenames and keyboard-layout cases in tests.
- Keep it free, without accounts, subscriptions, trial limits, activation,
  telemetry, or hosted inference. Network access belongs only in explicit
  installation/download commands. Normal image processing must work offline.
- On macOS, store models, dependencies and caches under
  `~/Library/Application Support/ncf-image-upscaler`, outside Git. Windows
  storage and packaging rules are in `apps/windows/AGENTS.md`.
- Preserve RGBA transparency, including partial alpha. Test colored edges on
  light and dark backgrounds; do not flatten images onto a background.
- Keep `imaging.upscale_image()` and the MLX engine independent of interface
  code. The Swift/AppKit app uses the JSON Lines worker; the CLI calls the same API.
- Never overwrite an input image. Existing CLI outputs require `--overwrite`;
  the app chooses a free filename or asks for confirmation in Save As.
- Preserve third-party attribution and BSD notices when editing vendored code.
  Record changes to vendored sources in `THIRD_PARTY.md`.
- Pin macOS dependencies in `uv.lock` and models in
  `src/ncf_image_upscaler/models.json`. Windows has separate locks and manifests.
  Never commit weights or include them in Windows installers/GitHub assets.
- Run the relevant pytest checks and Ruff. Integration tests use the actual
  local models and should not download anything.
- On macOS, run `scripts/test-native.sh` and build when changing Swift sources.
  Windows changes use their own component/worker/installer checks.
- Installed applications must work after the source checkout is removed.
  `scripts/install.sh --dev` is the explicit editable development mode.
- `work/` is ignored scratch space; `outputs/` is ignored local output space.
- Public reports must omit personal paths, usernames, hostnames, network
  identifiers and private images. Use safe fixtures and relative commands.

