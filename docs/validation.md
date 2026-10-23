# Validation record

Environment: Xcode 26.6, Swift 6.3.3, macOS host, iOS 26.5 SDK, iOS 17 deployment.

## Executed

[GitHub Actions run 1](https://github.com/rarce/wooloo-io/actions/runs/40004964572)
completed successfully for source commit `559506e2d8cd631e1f482c428f6ab7a984363538`:
12 tests passed, generated Xcode project matched, and the complete unsigned Debug
iOS simulator app build finished with **BUILD SUCCEEDED** (including app bundle,
assets, privacy manifest and notices). The app was not launched or visually inspected.


- SwiftPM core build for macOS.
- SwiftPM cross-compilation of the complete core/dependency graph, including
  SwiftTerm, for `arm64-apple-ios17.0-simulator`.
- 12 passing tests: snapshot order/geometry, unknown statuses, QR/link fingerprints
  and duplicate/malformed fields, transport preservation, split UTF-8 NDJSON,
  complete/incomplete oversized records, frame dimensions/base64, shell argument
  quoting, credential-free profile JSON; plus an actual NIOSSH handshake and
  bidirectional Citadel exec over an isolated local Unix socket pair, and unknown
  server identity rejection.
- SwiftUI/UIKit app typecheck against the iOS SDK and native executable link.
  `vtool` confirms platform IOSSIMULATOR, minimum iOS 17.0, SDK 26.5. This checks
  compilation and dependency linkage, not app-bundle resources or runtime behavior.
- Project/plist syntax validation using `plutil`.

The SSH fixture generates an ephemeral server key and uses a dummy password in
memory. It opens no TCP port, changes no `authorized_keys`, and touches no existing
Herdr session or user SSH configuration. It is a real SSH protocol test, with a
small fake Herdr response on the exec channel; it is not a real Herdr server test.

## Environment restrictions and alternate checks

This managed execution environment denies CoreSimulator service access and Xcode's
nested package-manifest sandbox. Consequently the command-line `xcodebuild` and simulator launch could not
be completed through the restricted shell. A subsequent native Xcode UI run
installed the official iOS 26.5 runtime, successfully built and launched the app
on iPhone 17, and opened the local demo spaces screen. Compilation caches were redirected
to disposable `/private/tmp` directories. GitHub dependency mirrors under that
same temporary directory were used because SwiftPM's child network access is
restricted. Those local mirror settings are ignored and are not shipped.

The app can be typechecked independently of CoreSimulator using:

```sh
swift build --scratch-path /private/tmp/wooloo-ios-spm \
  --triple arm64-apple-ios17.0-simulator \
  --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"
python3 scripts/typecheck-ios.py /private/tmp/wooloo-ios-spm
# Optional executable link check (not a distributable .app bundle):
python3 scripts/typecheck-ios.py /private/tmp/wooloo-ios-spm /private/tmp/WoolooMobile-simulator
```

The helper disables the compiler's nested subprocess sandbox only; the outer
workspace sandbox remains in effect. This alternate check is not a replacement
for a full Xcode build, simulator screenshots, on-device tests or a signed archive.
CI runs the normal tests and simulator build in an unrestricted macOS runner.

## Release gates still required

- Release simulator and Debug/Release device builds, visual checks on compact
  iPhone and iPad, rotation, accessibility and hardware/software keyboards.
- Direct SSH against an isolated real Herdr session: snapshot/events, every remote
  action, terminal frames/input, automatic control/confirmed takeover, release, timeout/cancel,
  resize, session closure and reconnection.
- Cloudflare quick tunnel and named/Access tunnel: valid/invalid tokens, TLS and
  redirect refusal, network loss, backpressure, clean shutdown and foreground return.
- Keychain on a real unlocked/locked device, key generation/import, profile edits,
  credential clearing, QR camera/photo and notification routing.
- Review privacy manifest, App Store metadata and export compliance; choose a
  signing team only when available. No App Store upload is attempted by this repo.

## Local manual-review startup

The first native Xcode Run exposed a Debug architecture mismatch: the app tried
to compile Intel simulator code while SwiftPM generated the active ARM64 variant.
Debug now sets `ONLY_ACTIVE_ARCH = YES` in the deterministic project generator.
Rebuilding through Xcode successfully launched Wooloo Mobile on iPhone 17 with
iOS 26.5. The demo spaces screen was left open for manual review. Full navigation,
terminal/keyboard, accessibility and real-server QA remain pending.

## Default terminal control

Removed the Watch/Control selector. Opening a pane requests ordinary control
automatically, including after foreground/SSH recovery. Taking control from another
client still requires the explicit confirmation. The terminal releases control on
leaving; reconnect is available from its menu after a failure.

Validated with the iOS typecheck helper and a native Xcode rebuild/run on iPhone 17
(iOS 26.5). Entering the demo pane immediately rendered its terminal with enabled
extra keys and no mode selector. Real-server ownership conflict validation remains
pending.
