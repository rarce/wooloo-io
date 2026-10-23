# Security

Do not post credentials, private keys, Cloudflare tokens or private terminal output
in public issues. For a suspected vulnerability, use GitHub's private vulnerability
reporting if enabled, or contact the maintainer through their GitHub profile before
sharing details. Do not send secrets to demonstrate a report.

This is an early source preview. Review the destination and SHA256 host fingerprint
before connecting. Keychain entries use `WhenUnlockedThisDeviceOnly`; server
identity is checked before SSH authentication. Cloudflare TLS uses the platform
trust store and Access headers cannot follow redirects.

Known boundaries: one active machine, foreground SSH only, no background relay or
push service, no unofficial quota access. Physical-device, real Herdr/Cloudflare,
accessibility and release-signing acceptance checks are still pending. See
`docs/validation.md` and `docs/phase-status.md`.
