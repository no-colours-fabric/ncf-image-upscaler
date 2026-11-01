# Platform architecture

Status: agreed direction for documentation; Windows implementation and research
execution are separate steps. This document records proposals where stated and
does not announce a Windows application.

## Current product and repository

The available application and CLI target macOS on Apple Silicon. Windows is
experimental research: no Windows binary, supported hardware minimum, performance
claim, or release date is available. Windows 11 x64 is the proposed research
target; Windows 10 and ARM64 are unvalidated. A 16 GB test machine would be a
measurement configuration, not a minimum RAM requirement.

Keep one repository with two independently delivered platform applications.
Preserve the current `native/`, `src/`, model manifest, dependency lock, installers,
and macOS DMG workflow. Do not move them or create empty implementation directories
to illustrate a future layout. Introduce shared executable code only after its
compatibility is demonstrated.

## Shared behavior and visual principles

- Remain free, without accounts, telemetry, activation, subscriptions, or hosted
  inference. Normal processing is offline; downloads require explicit installation
  or model-download actions. Pin dependencies and model artifacts, verify hashes,
  preserve licenses, and keep weights and runtime environments outside Git.
- Never replace an input. CLI replacement of an existing output requires explicit
  `--overwrite`; even that flag must not replace the input. The app chooses an
  unused output filename or confirms replacement in Save As. An unsupported
  filesystem may fail safely with an English explanation; never silently weaken
  no-overwrite guarantees.
- Preserve RGBA and partial alpha without flattening, including colored edges over
  light and dark backgrounds. Retain the declared 8-bit RGB/RGBA, EXIF orientation,
  and embedded ICC behavior. Describe alpha resizing separately from RGB inference.
- Use English interfaces, documentation, and diagnostics. The target common feature
  set is scales ×1/×2/×4 and Photo/Illustration/Fast presets. This is a goal for
  separate applications, not a claim of implemented Windows parity or equal quality.
- Keep comparable visual organization: folder and image selection, original/result
  comparison, zoom, transparency checkerboard, model/scale controls, progress,
  cancellation, and a separate save action. Native controls may differ. Show the
  actual computation backend and explain any CPU fallback.

## Platform boundaries and data

macOS retains Swift/AppKit, Python/MLX, and the existing data root
`~/Library/Application Support/ncf-image-upscaler`, including explicit overrides.
The current macOS installation must remain independent of the source checkout
except in explicit development mode.

For Windows, C#/WPF on a pinned .NET LTS and Python/ONNX Runtime are candidates,
not selected product requirements. The proposed Windows data root is
`%LOCALAPPDATA%\NCF Image Upscaler`, with separate model, runtime, and cache
subdirectories. Confirm this policy before implementation. Do not apply the macOS
storage path mechanically to Windows.

`imaging.py` defines an MLX-independent `ImageEngine.upscale(rgb, progress)`
interface. It is a potential reuse boundary for RGBA/ICC/EXIF processing, subject
to Windows dependency, Unicode-path, and filesystem-publication checks. Current
CLI/worker engine construction, MLX model artifacts, and path logic are platform
specific. Shared behavior specifications and fixtures remain useful even if
runtime implementations differ. Do not require a shared runtime prematurely.

The existing macOS worker is a single subprocess launched with arguments, not a
persistent request server. Its stdout carries JSON Lines events:

| Event | Current meaning |
| --- | --- |
| `started` | Input and model prechecks passed; estimated tile count and input dimensions are available, before engine construction. |
| `progress` | A tile completed; completed and total tile counts are reported. |
| `completed` | Output was saved; path, dimensions, scale, model, and elapsed seconds are reported. Normal exit is 0. |
| `error` | A caught exception is reported; exit is 1. Failures outside this handler need not emit this event. |
| `cancelled` | Python caught `KeyboardInterrupt`; exit is 130. |

Distinguish JSON events, process exit status or signal, and user cancellation. The
macOS UI interrupts the worker and escalates to termination, then forced killing
if needed. UI cancellation does not guarantee a `cancelled` JSON event. This is a
description of existing behavior, not a requirement to change macOS. A future
shared protocol must document these lifecycle details and compatibility explicitly.

## Dependencies, CI, versions, and releases

Keep macOS dependency/model pins and its release process unchanged. Windows research
needs a separate exact environment lock and model manifest. Record the source
revision and hash, export code/settings, exported ONNX hash, license, and runtime
compatibility. MLX safetensors are not ready-to-use ONNX artifacts. Model export
tooling need not be shipped in the end-user runtime.

Use explicit platform CI, packaging, and validation. Integration checks use prepared
local models and never download them. CPU research success does not validate GUI,
installer, GPU, or full preset compatibility. Historical macOS results remain
macOS-only; report missing checks honestly.

Propose independent application versions while preserving existing `v*` tags,
including `v0.4.0`, release history, and the current macOS `v*` workflow. A future
Windows release could use `windows-v0.1.0`, with a separate workflow verified not
to trigger macOS publication. This is a naming proposal, not an implemented
migration. Any future macOS tag migration or shared protocol version is a separate
decision. Never publish Windows availability before a verified Windows release.

## Next research step: one CPU model

After separate authorization, prepare an isolated CLI/worker experiment using one
fast/SRVGG ONNX artifact and an exactly pinned environment. Explicitly select and
verify only `CPUExecutionProvider`. Downloads occur only during explicit preparation.
No GUI or GPU backend is required for this experiment.

Acceptance criteria:

1. Record CPU, RAM, OS build, environment/package versions, model/export provenance,
   ONNX SHA-256, provider configuration, and reproducible commands.
2. Run inference after preparation with network access actually blocked. Record
   the blocking mechanism; absence of download calls alone is insufficient.
3. Exercise RGB and partial-alpha RGBA fixtures at specified 512- and 1024-pixel
   dimensions, plus a larger synthetic or publication-safe photograph. Record
   exact input/output dimensions, scale, elapsed time, peak process memory, and
   measurement method, including whether setup time and child processes count.
4. Verify unchanged input bytes, preservation of an existing destination without
   explicit overwrite, input/output alias protection even with overwrite enabled,
   and no-clobber behavior if another process creates the destination during
   inference. Include Unicode filenames and spaces; report filesystem limitations.
5. Check alpha against documented target-size behavior and colored partial-alpha
   edges against light/dark backgrounds; check orientation and ICC retention.
   Assess RGB differences separately. Bitwise equality with MLX is not required,
   and one fast artifact does not establish Photo/Illustration/Fast quality parity.
6. Report actual backend, progress/cancellation behavior, internal model scale,
   final resizing, failures, and resource limits. Current ×1 processing still
   performs neural upscaling followed by reduction; Fast uses internal ×4. Small
   tiles alone do not limit total RAM: the current macOS tiler allocates a full
   float32 RGB output (about 2.3 GB for 4000 × 3000 input at ×4, before other data).

Public reports must exclude usernames, personal paths, hostnames, serial numbers,
local IP addresses, and private photos. Use relative commands and variables, safe
fixtures with checksums, and only necessary hardware/OS/version details.

The deliverable is a reproducible experiment report and a decision on continuation,
not a Windows release or hardware guarantee. Review CPU correctness, latency, and
memory before testing an integrated GPU. Choose GPU APIs, GUI, and packaging after
the relevant evidence. Normal processing must remain offline with any provider.

## Follow-up decisions

Agree the experiment location, external artifact storage, Windows data root, exact
export/runtime versions, test machine, and useful task latency before running the
experiment. Add Windows-scoped rules only alongside real implementation files.
No experiment report or Windows implementation directory exists as part of this
documentation step. Existing validation is recorded in
[verification notes](../verification.md); it supplies no Windows inference results.
