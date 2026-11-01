# NCF Image Upscaler

- The available product is an independent native macOS app and CLI for Apple
  Silicon. Windows is experimental research, with no supported application yet.
  Follow `docs/architecture/platforms.md`; do not imply Windows availability.
- Use English for the interface, documentation, diagnostics, and contributions.
  Keep Unicode filenames and keyboard-layout cases in tests.
- Keep it free, without accounts, subscriptions, trial limits, activation,
  telemetry, or hosted inference. Network access belongs only in explicit
  installation/download commands. Normal image processing must work offline.
- Keep models, installed dependencies, runtime environments, and installation
  caches outside Git. On macOS, store them under
  `~/Library/Application Support/ncf-image-upscaler`.
  The Windows data root `%LOCALAPPDATA%\NCF Image Upscaler` is a proposal,
  not an implemented storage policy. Agree its implementation separately.
- Preserve RGBA transparency, including partial alpha. Test colored edges on
  light and dark backgrounds; do not flatten images onto a background.
- Keep `imaging.upscale_image()` and the MLX engine independent of interface
  code. The Swift/AppKit app uses the JSON Lines worker; the CLI calls the same API.
- Never overwrite an input image. Existing CLI outputs require `--overwrite`;
  the app chooses a free filename or asks for confirmation in Save As.
- Preserve third-party attribution and BSD notices when editing vendored code.
  Record changes to vendored sources in `THIRD_PARTY.md`.
- Pin macOS dependency versions in `uv.lock` and model revisions/hashes in
  `src/ncf_image_upscaler/models.json`. Future Windows research needs separately
  pinned dependencies and model artifacts; do not add them to the macOS runtime.
  Never commit downloaded weights.
- Run the relevant pytest checks and Ruff. Integration tests use the actual
  local models and should not download anything.
- On macOS, run `scripts/test-native.sh` and build the app when changing Swift
  sources. These checks do not validate Windows.
- Normal macOS installation must work after the source checkout is removed.
  `scripts/install.sh --dev` is the explicit editable development mode.
- `work/` is ignored scratch space; `outputs/` is ignored local output space.
- Keep public reports free of personal paths, usernames, hostnames, serial
  numbers, local IP addresses, and private images. Use relative commands and
  variables; publish only necessary hardware/OS/version details and safe fixtures.

