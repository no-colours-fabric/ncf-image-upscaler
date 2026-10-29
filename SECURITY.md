# Security policy

Image Upscaler is an early-stage local application. Security fixes target the
latest published release; older releases do not have a separate support branch.

## Reporting a vulnerability

Use the repository's **Security → Report a vulnerability** option when available.
If private reporting is unavailable, open an issue asking for a private contact
channel, without exploit details, sensitive files, or personal information.
Do not publish a working exploit in a public issue before coordination.

Include the affected version, macOS/Python versions, a minimal reproduction,
and the expected impact. Share only images and logs you are allowed to disclose.
There is no guaranteed response time or paid support service.

## Scope

Normal inference is local and offline. Network access is limited to explicit
installation and model-download commands. Model files are pinned by revision,
size, and SHA-256; no automatic download occurs during processing.

The app parses image files, invokes a local Python worker, and offers file
management operations. Findings involving unsafe writes, input replacement,
path handling, unexpected network access, or malicious image handling are relevant.
