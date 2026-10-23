# Implementation phase status

2026-10-23. Product: **Wooloo Mobile**, iOS 17+. This is a source preview, not a
claim that every release acceptance criterion in the Astra roadmap has passed.

| Astra phase | Implemented in this repository | Remaining acceptance/scope |
|---|---|---|
| 1 · Foundation/demo | SwiftUI navigation, deterministic local demo, state colors, geometry miniatures, SwiftPM core, generated/committed Xcode project, Wooloo icon | Simulator visual QA, Dynamic Type/VoiceOver and iPad checks |
| 2 · Secure SSH | Device-local Keychain, Ed25519 generation/export/import, password auth, server pins, destination review, legacy links and QR/photo import | Device Keychain/import and camera tests, wider key format support, richer first-trust UX |
| 3 · Herdr state | NDJSON API, response ID validation, snapshots, lifecycle subscription, bounded requests, agent prompts, workspace/tab creation, space rename/close, pane split/zoom/close, cached state, bounded reconnect | Real Herdr 0.9.5/protocol 22 integration, wider management UI, multi-machine connections |
| 4 · Terminal | SwiftTerm ANSI rendering, ordered bounded frames, native keyboard, quick keys, explicit control/watch/takeover/release, resize, multiline composer | Real server control conflicts, remote scrollback gestures, mouse, image attachments, device IME/rotation tests |
| 5 · Cloudflare/iOS | Binary WebSocket-to-SSH transport through a local socket pair, default TLS, redirect refusal, bounded messages/backpressure, Access tokens in Keychain, foreground lifecycle/network recovery, local notifications | External quick/named/Access tunnel tests, lifecycle/device soak; background SSH/push deliberately not included |
| 6 · Publication | Public GitHub repository, MIT/license notices, privacy/security documentation, CI, signing-neutral Xcode configuration | Release signing, App Store privacy/export review, paid membership/TestFlight and device acceptance |

## CI result

[GitHub Actions run 1](https://github.com/rarce/wooloo-io/actions/runs/40004964572)
passed all 12 tests, deterministic project generation and the full unsigned Debug
iOS simulator build for source commit `559506e`. Runtime/visual and real-server
acceptance checks above are still pending.

## Dependency correction found during implementation

An actual SSH handshake/exec fixture exposed two upstream Citadel issues: off-loop
synchronous NIO pipeline mutation, and an `Already closed` cleanup race when an
exec server closes after its response. The vendored copy records its upstream
revision and both patches in `Vendor/Citadel/UPSTREAM.md`. Tests now exercise both
the real SSH exec path and rejection of an unknown server fingerprint.

## Scope decisions

A mobile companion does not embed Herdr, provider APIs or coding agents. The existing
Android app contains additional features and is the wire-format reference, not a
promise of full parity in 0.1.0. Follow-up features are explicitly listed above and
in README. The unpaid Apple account does not block source/simulator development;
distribution remains a later step.
