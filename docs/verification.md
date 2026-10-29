# Verification notes

## Publication preparation — 2026-10-29

Environment: Apple M4 Pro, macOS 26.5.2, Python 3.14.4, MLX 0.32.4.
Runtime and verified models are stored under Application Support.
These are local results, not claims that GitHub Actions has already run.

| Check | Result |
| --- | --- |
| Python unit checks (`pytest -m 'not integration'`) | 26 passed; 11 integration tests deselected |
| Actual GPU integration checks (`pytest -m integration`) | 11 passed; 26 unit tests deselected; no model downloads |
| Native checks (`scripts/test-native.sh`) | 468 assertions passed, including the local worker bridge |
| Ruff lint and formatting | Passed |
| Shell syntax and GitHub YAML syntax | Passed locally |
| Source archive and Python wheel | Built; manifests, vendored code, and license inclusion checked |
| Non-editable source installation | Verified in an isolated runtime on this Mac |

### Installation independence

A fresh source archive was extracted into a temporary directory under Application
Support. The pinned dependencies were installed into a separate environment using
`uv sync --locked --no-dev --no-editable --offline`. This used the existing package
cache and did not download models. A separate command symlink was registered
without changing the user's shell profile or installed command.

The native app was built from that copy. The extracted source directory was then
deleted. From a different working directory, the installed CLI printed its version,
passed `doctor`, imported the package from `site-packages`, and enhanced a synthetic
RGBA image at ×4. The app's configured Python worker completed ×1 inference.
The built production app also launched with that fixture after source removal.
The original image bytes were unchanged. Its local signature and all packaged
license texts were checked. The isolated test runtime was removed afterward.

This validates source-folder independence on the tested Mac. It does not replace
installation testing on a separate physical machine or testing every supported
macOS/Python combination.

### Native interface

The English app was built and opened with a project-generated RGBA sample.
Photo ×4 processing completed through the actual interface; the original/result
divider, English controls, transparent background, and save operation were observed.
The result was saved separately and the test app was closed. Documentation uses
an unedited application screenshot, not a user's image or a mockup.

### Restricted-environment MLX crash

One initial integration-test invocation in Codex's restricted execution environment
aborted while importing `mlx.core`, before image processing. The macOS crash report
identified SIGABRT inside the native MLX extension. The same 11 integration tests
then passed with normal Apple GPU access. The report does not expose the exact
internal reason for `abort()`; restricted GPU access is the likely explanation,
not a proven internal diagnosis. Python exception handling cannot catch a native
process abort. GPU checks must run in an environment that exposes Metal.

### Source and history review

The pre-publication local history (four commits, 78 unique tracked blobs) and publication files
were checked for common credential/token/private-key patterns. No matches, model
weights, or large historical binary files were found. This is a pattern-based
review, not a guarantee of detecting all confidential information.

The original local history contained a personal commit email and older local
paths in the README. The public repository starts with one new root commit using
the GitHub account's noreply address. The original development history is kept
only in a local archive branch; it is not part of the public branch's ancestry.

Upstream implementation files were compared with the pinned MLX-port revision.
All four pinned model cards were inspected. The BasicSR Apache-2.0 license and
the adapted package initializers are now accounted for in `THIRD_PARTY.md`.

## Earlier local validation — October 2026

The previous development record reported 35 Python tests (including 11 GPU tests)
and 468 native assertions on the same hardware. It also recorded processing with
an operating-system network-denial profile, ad-hoc signature verification, Finder
Open With registration, and manual viewing of transparent colored edges on light
and dark backgrounds. These are historical observations, not newly repeated
network-denial or Finder-registration checks during publication preparation.

The automated suite covers these existing behaviors:

- RGBA, grayscale alpha, palette transparency, transparent-color PNG, EXIF
  orientation, PNG output, and preservation of the original file.
- Exact alpha preservation at ×1; direct Lanczos alpha resizing at ×2/×4;
  invariance to hidden black versus white RGB; colored partial-alpha blending
  against light and dark backgrounds.
- Missing/corrupt weights fail without automatic downloads; downloads verify
  hashes before publishing a model file.
- Safe output naming and atomic writes, including symbolic/hard-link protection.
- Folder filtering/sorting, selection ranges, physical-key navigation across
  layouts, regular/adaptive grids, viewport scrolling, and persisted preferences.
- Session thumbnail reuse, RAM/disk eviction, invalidation after file changes,
  cancellation of stale loads, and loading placeholders.
- File operations, clipboard paths and image transparency, undo/redo, folder
  monitoring, and retaining unsaved results when an original disappears.
- Shared comparison coordinates, zoom/pan constraints, fitting and 100% toggling,
  fixed transparency checkerboard, asynchronous image changes, unsaved-result
  resolution, and native worker progress/cancellation.

Synthetic fixtures verify functionality and transparency, not a universal claim
about artistic image quality. Evaluate the chosen model on representative images.
