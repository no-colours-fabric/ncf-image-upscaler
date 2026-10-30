# Changelog

## 0.4.0 — 2026-10-30

- Rename the application and repository to NCF Image Upscaler.
- Use `ncf-upscale` for the CLI and `ncf_image_upscaler` for the Python package.
- Use `ncf-image-upscaler` for Application Support data and a new macOS bundle identifier.
- Reuse verified models from pre-0.4 installations offline, and copy existing sidebar preferences on first launch.
- Update the installer, release assets, documentation, and GitHub links for the new name.

## 0.3.0 — 2026-10-29

- Standalone Apple Silicon DMG with a pinned, relocatable Python/MLX engine.
- Offline first-launch engine extraction into Application Support; no system Python or Xcode required.
- Native model setup with explicit downloads, verification, progress, and cancellation.
- Bundled CA certificates for model downloads and full runtime/component license notices.
- Local ad-hoc signatures, explicit non-notarized-build instructions, and a published SHA-256 checksum.
- Release workflow builds and verifies a relocated installation before publishing assets.


## 0.2.0 — 2026-10-29

First public source release for macOS on Apple Silicon.

- Native Swift/AppKit folder browser with thumbnail grids, filtering and sorting,
  keyboard navigation, file operations, and original/result comparison.
- Local MLX inference with Photo, Illustration, and Fast presets at ×1, ×2, and ×4.
- Independent transparency handling, including partial alpha and soft edges,
  with safe, separate PNG outputs.
- Command-line tool, explicit model download/verification, and a JSON Lines native worker.
- English interface, command-line help, diagnostics, and documentation.
- Regular installations work independently of the source folder; editable
  development remains available through `--dev`.
- Automated unit, native, formatting, build, archive, and source-installation checks.
- Contribution guidance, issue templates, security policy, and third-party notices.

### Requirements and limitations

macOS 14 or later, Apple Silicon, and Python 3.12–3.14 are required. The native
app is built locally from source using Xcode Command Line Tools. A portable app
binary is not included in this release. Image processing uses 8-bit RGB/RGBA;
animations, multipage images, HDR, and 16-bit workflows are unsupported.
