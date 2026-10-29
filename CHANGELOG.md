# Changelog

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
