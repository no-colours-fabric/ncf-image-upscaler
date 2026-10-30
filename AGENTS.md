# NCF Image Upscaler

- This is an independent native macOS app and CLI for Apple Silicon.
- Use English for the interface, documentation, diagnostics, and contributions.
  Keep Unicode filenames and keyboard-layout cases in tests.
- Keep it free, without accounts, subscriptions, trial limits, activation,
  telemetry, or hosted inference. Network access belongs only in explicit
  installation/download commands. Normal image processing must work offline.
- Store models, installed dependencies, runtime environments, and installation
  caches under `~/Library/Application Support/ncf-image-upscaler`, outside Git.
- Preserve RGBA transparency, including partial alpha. Test colored edges on
  light and dark backgrounds; do not flatten images onto a background.
- Keep `imaging.upscale_image()` and the MLX engine independent of interface
  code. The Swift/AppKit app uses the JSON Lines worker; the CLI calls the same API.
- Never overwrite an input image. Existing CLI outputs require `--overwrite`;
  the app chooses a free filename or asks for confirmation in Save As.
- Preserve third-party attribution and BSD notices when editing vendored code.
  Record changes to vendored sources in `THIRD_PARTY.md`.
- Pin dependency versions in `uv.lock` and model revisions/hashes in
  `src/ncf_image_upscaler/models.json`. Never commit downloaded weights.
- Run the relevant pytest checks and Ruff. Integration tests use the actual
  local models and should not download anything.
- Run `scripts/test-native.sh` and build the app when changing Swift sources.
- Normal installation must work after the source checkout is removed.
  `scripts/install.sh --dev` is the explicit editable development mode.
- `work/` is ignored scratch space; `outputs/` is ignored local output space.

