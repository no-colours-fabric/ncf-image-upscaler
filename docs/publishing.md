# Publishing and release checklist

Repository: <https://github.com/no-colours-fabric/image-upscaler>.

Use this checklist for source releases. Local verification and hosted CI results
are separate; check the Actions run for the exact commit being released.

## Before the first push

1. Review the final diff and commit the intended changes. Existing unrelated
   local work must be reviewed before inclusion. Keep local images, weights,
   environments, and generated output outside the commit.
2. The public branch starts with a single root commit using the GitHub noreply
   identity. Original development history is preserved in a local archive branch.
   Push only the public branch and intended release tags; do not push all branches
   or mirror the local repository, since the archive retains private history.
3. Recheck the current tree and all intended history for credentials and private
   files. The local preparation audit found no credential-like secrets or model
   weights in the reachable tracked history; this is a pattern-based check,
   not a guarantee that all sensitive information can be detected.
4. Create a public repository named `image-upscaler` with the display name
   **Image Upscaler**. Suggested description: **Offline AI image enhancement for
   Apple Silicon. Native macOS app and CLI, with transparency support.**
5. Keep the actual Homepage/Repository/Issues links in package metadata and
   installation examples consistent with the repository URL above.
6. Enable private vulnerability reporting, review Actions permissions, and set
   the CI check as a required check for pull requests after it has run successfully.
   Suggested topics: `macos`, `apple-silicon`, `image-upscaling`, `mlx`, `realesrgan`,
   `offline`, `swift`, `python`.

## Validate a release candidate

- Run the checks in [CONTRIBUTING.md](../CONTRIBUTING.md).
- Run all GPU integration tests with verified local models on a Mac with Metal.
  Tests that skip because of absent weights do not validate inference.
- Check transparent colored edges and partial alpha on light and dark backgrounds.
- Build the native app and verify its local signature.
- Test a normal, non-editable installation from a fresh source copy; check that
  the CLI and app still work after moving that copy.
- Build source/Python archives into Application Support and inspect their contents:

  ```sh
  APP_HOME="$HOME/Library/Application Support/image-upscaler"
  UV_CACHE_DIR="$APP_HOME/cache/uv" "$APP_HOME/runtime/tooling/bin/uv" build --no-sources --out-dir "$APP_HOME/runtime/distributions"
  "$APP_HOME/runtime/env/bin/python" scripts/check-distributions.py "$APP_HOME/runtime/distributions"
  "$APP_HOME/runtime/env/bin/python" scripts/check-source-install.py "$APP_HOME"/runtime/distributions/*.tar.gz
  ```

- Keep versions consistent across `pyproject.toml`, `src/image_upscaler/__init__.py`,
  `native/Info.plist`, `uv.lock`, release notes, and the chosen tag. The initial
  source version is `0.2.0`. Release tags use the `v` prefix, such as `v0.2.0`.
- Review `THIRD_PARTY.md` and include all license texts. Downloaded model weights
  must never be committed or attached to a source release.
- Use only screenshots and examples whose publication rights are clear. The
  documentation preview uses a project-generated synthetic sample, not a user's image.

## Publish

Commit and push the approved tree, wait for hosted CI, then create the matching
version tag and GitHub release. Record the changes in a dated changelog entry. Release notes should describe installation from
source, supported platforms, limitations, and the validation actually performed.

The initial distribution is source-based. The locally built app contains a path
to its local runtime and is ad-hoc signed. Do not upload that app as a portable
binary release. A standalone app download would need a separate packaging,
dependency-notice, signing, and distribution process.
