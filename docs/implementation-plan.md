# Wooloo Mobile for iOS — implementation plan

Status: implementation roadmap, based on the local Wooloo macOS and Android source on 2026-10-23. Completion of a phase requires its acceptance checks; this document does not claim those checks have run.

## Product and scope

Build a native SwiftUI companion for existing Herdr servers. The primary journey is **Machines → Spaces → Agents/panes → Terminal or message composer**. Preserve Wooloo's visual vocabulary, state colors and pane layout miniatures while using iOS navigation, Dynamic Type, VoiceOver and keyboard conventions. Include a fully local, clearly labeled demo so the app can be explored without credentials.

Android is the mobile wire-protocol reference. The macOS binary terminal surface and AppKit renderer are a separate client path and should not be copied as the mobile transport. This app does not run Herdr or coding agents on the phone. Desktop file editing and Git workflows are outside the first mobile release.

Target iOS 17+ with the available Xcode 26.6; use a SwiftPM core that also supports macOS 15 for host-side tests. Initial implementation selects Citadel for SSH (locally inspected revision `ae8562f895de06ccb86fdb1cbb65fd99c8976e12`, including bidirectional exec and custom host-key validation) and SwiftTerm for the UIKit terminal renderer; validate and pin resolved dependencies before claiming live support. Use SwiftUI for app screens, an isolated terminal model and a UIKit-backed terminal input/rendering surface where necessary. Keep transport and protocol modules independent of UI so they can be tested with fixtures.

## Reference map

- `../herdroid/AGENTS.md`, `README.md`: architecture, security constraints and mobile feature behavior.
- `../herdroid/app/src/main/java/dev/herdroid/herdr/Models.kt`: authoritative snapshot shape, display-label precedence, state labels and layout ordering.
- `../herdroid/app/src/main/java/dev/herdroid/herdr/HerdrApi.kt`: request/response envelopes, commands, event subscription and deadlines.
- `../herdroid/app/src/main/java/dev/herdroid/herdr/TerminalStream.kt`: terminal records, input/control and bounds.
- `../herdroid/app/src/main/java/dev/herdroid/herdr/RemoteCommand.kt`: shell quoting, explicit Herdr path and executable discovery.
- `../herdroid/app/src/main/java/dev/herdroid/data/HostLink.kt`: existing QR/deep-link compatibility and machine matching.
- `../herdroid/app/src/main/java/dev/herdroid/ssh/`: SSH and Cloudflare byte transports.
- `../wooloo/AGENTS.md`, `README.md`, remote-access implementation: desktop interaction and onboarding interoperability.

Local reference repositories remain unchanged. Inspect public website branding separately before copying assets; preserve applicable licenses and notices for any reused code or assets.

## Phase 1 — native foundation and reviewable demo

Create the Xcode app/project, application identity, assets, structured logging with privacy redaction, a protocol/model module and deterministic fixtures. Build the main navigation, grouped machine/space/agent lists, state badges, real pane-geometry miniature, terminal screen and multiline composer. Demo actions should change simulated state consistently and must never imply a real network connection.

Persist nonsecret machine profiles separately from secrets. Establish interfaces for SSH transport, exec channels, Herdr requests, terminal streams, secret storage and connection lifecycle before attaching a real backend. Display explicit unsupported/unavailable errors for any real transport capability not yet implemented.

Acceptance: simulator build; demo journey on compact iPhone and larger iPad widths; accessible labels; Dynamic Type layout; fixture decoding tests; clean build from documented commands.

## Phase 2 — secure direct SSH and connection onboarding

Select and pin an iOS-compatible SSH implementation after verifying its API, supported host-key/auth algorithms, license and integration tests. It must support multiplexed exec channels and explicit host-key verification. Use a single SSH transport per machine; do not shell out to a system SSH binary on iOS.

Implement password and supported key authentication, Ed25519 generation/public-key export and clearly enumerated supported import formats. Private keys, passwords and Cloudflare secrets belong in Keychain with device-local protection, never profile JSON, UserDefaults, demo data or logs. Do not silently downgrade failed key imports or verification.

Implement host-key TOFU confirmation and persisted trust. Imported pins must be enforced before authentication; changed keys must block connection until explicitly reviewed. Changing a profile's destination or pins requires renewed trust review before reusing stored credentials.

Support pasted `herdroid://add-host` links immediately and camera/image QR scanning next. Fields: `transport=ssh|cloudflare` (SSH default), `host`, `port`, `user`, `session`, `label`, absolute `herdr` path and repeated `fp=SHA256:…`. Preserve literal plus signs in fingerprints. A link fills an editor; it never connects or grants credentials. Match direct hosts by address/port/user/session and rotating Cloudflare tunnels by nonempty label/user/session, always reviewing destination changes.

Acceptance: isolated SSH fixture; correct authentication; unknown/changed/pinned host-key scenarios; canceled trust review sends no credentials; imported malformed links rejected; Keychain/profile separation; no secret-bearing fixtures.

## Phase 3 — live Herdr state and agent interaction

Execute `herdr --session <session> remote-api-bridge` using safely quoted arguments and noninteractive executable discovery. Each API request uses a fresh exec channel on the shared SSH connection and sends a newline-delimited `{id, method, params}` object. Responses carry `result` or structured `error`; `session.snapshot` returns `result.snapshot`.

Use a persistent bridge channel for `events.subscribe`. Subscribe to lifecycle and pane agent-state changes; events invalidate cached state, and fresh snapshots remain authoritative. Handle lost events by resubscribing and reconciling. Coalesce refreshes, preserve server ordering, and avoid generating a notification storm on initial snapshots. Unknown fields and statuses must decode safely.

Implement workspace/tab create, rename and close; pane focus, split, rename, close and zoom; `agent.prompt`; quick replies through `pane.send_keys`; and bounded `pane.read` for copy/history. Confirm destructive close operations. Errors must identify corrective action without exposing credentials.

Use bounded request concurrency (Android reference: four), a 20-second deadline including channel acquisition, cancellation-aware IO and bounded cleanup. Keep all transport work off the main actor. Retain last snapshot with an explicit stale/disconnected indicator; use reconnect backoff and refresh immediately after network/foreground recovery.

Acceptance: live isolated Herdr session, no primary-session mutations; state refresh after every lifecycle action; proper ordering; timeouts/cancellation; recovery after connection loss; sanitized errors; compatibility checks against a documented server version (Android reference validated Herdr 0.9.5/protocol 22).

## Phase 4 — production terminal and shared control

Open `herdr --session <s> terminal session control <pane> --cols C --rows R`; add `--takeover` only following an explicit user decision. Offer observe mode through `terminal session observe`. On navigation or shutdown, release control and close channels cleanly. Never steal control automatically during reconnect.

Decode bounded NDJSON `terminal.frame` records (`seq`, `width`, `height`, `full`, base64 `bytes`) and `terminal.closed`. ANSI bytes describe full or partial screen updates, so use a real terminal emulator/model; stripping ANSI into a text view is not parity. Preserve incremental parsing across records, Unicode width, attributes, cursor, erase semantics and alternate-screen behavior. Avoid dropping incremental frames in a UI latest-value queue; update the model in order and coalesce rendered snapshots only.

Port reference bounds: dimensions 1…512, at most 65,536 cells, decoded frame at most 1 MiB, record at most 1.5 million characters. Bound outbound queues and fail visibly if input cannot be accepted. Send `terminal.input` with text or base64 bytes, `terminal.resize`, `terminal.scroll`, `terminal.mouse` and `terminal.release`.

Support iOS marked text/dictation with committed-text correctness, a reliable multiline agent composer, hardware keyboards, sticky modifiers, repeat arrows, paste, scrollback, pinch font sizing and pane switching. Copy screen/history and open links only through explicit user actions. Screen dimensions must account for safe areas and the keyboard.

Acceptance: ANSI fixtures and Unicode/erase regression tests; live shell and agent TUI; ownership conflict/watch/takeover; resize/rotation; IME composition and dictation on device; queue saturation; background/resume; sustained-output memory/performance checks.

## Phase 5 — Cloudflare and mobile lifecycle

Adapt the SSH byte transport to binary WebSocket messages at `wss://<hostname>/`, matching Android's Cloudflare implementation. Optional service-token headers are `CF-Access-Client-Id` and `CF-Access-Client-Secret`; keep TLS validation enabled and prevent credential forwarding to an unreviewed destination. Cloudflare transport must expose the same SSH host-key verification and channel semantics as direct SSH.

Design background behavior around supported iOS execution limits. Release or suspend streams deliberately, preserve UI state and reconnect/resnapshot on activation. Foreground/local notifications can report observed state transitions; do not advertise uninterrupted background monitoring without a separately designed push service and device validation. Quota integrations remain deferred: they require separate per-identity consent and a documented provider compatibility review.

Acceptance: isolated named/quick-tunnel fixture, service-token failures, destination changes, repeated network changes, lock/unlock and foreground restoration on a physical iPhone. Document any remaining unsupported feature clearly.

## Phase 6 — public repository and release readiness

Use the explicitly requested public repository name `rarce/wooloo-io`; the local checkout name may remain `wooloo-ios`. Before first publication, inspect the staged content and history for private keys, passwords, tokens, real machine addresses, personal paths, signing assets and captured terminal/agent content. Use synthetic fixtures. Ignore build output, local credentials, Xcode user state and signing material. Include README, license, notices, privacy information, security reporting guidance, contribution instructions and reproducible CI build/test commands.

Provide a capability matrix marking implemented, demo-only, unvalidated and deferred features. Verify a clean simulator build and automated protocol/security regressions before publishing. The user currently has no paid Apple developer account: prioritize Simulator and personal signing where available, with TestFlight/App Store distribution as future work. Device signing and ongoing background notifications are separate release gates; do not describe a simulator-tested foundation as a production release.

Release acceptance: clean checkout builds; checks pass; live SSH and terminal results recorded with server version; physical-device input/lifecycle checks; dependency/license inventory; secret scan and staged diff review; no undocumented feature placeholders.
