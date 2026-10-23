# Wooloo Mobile · iOS

A native iPhone and iPad companion for [Wooloo](https://wooloo.dev) and
[Herdr](https://herdr.dev). Follow your spaces and coding agents, send prompts,
and operate their live terminals over SSH.

**Status: early source preview, 0.1.0. Not yet distributed through TestFlight or the
App Store.** The public repository is [rarce/wooloo-io](https://github.com/rarce/wooloo-io).
The app's display name is **Wooloo Mobile**, matching the Android app.

## Included

- Native SwiftUI machines → spaces → agents/panes navigation; server state colors,
  pane geometry miniatures and a clearly labeled local demo.
- Direct SSH and SSH over a Cloudflare Tunnel's binary WebSocket. No additional
  server software beyond SSH and Herdr, no Wooloo account or relay.
- Ed25519 device key generation, public-key copy/share and OpenSSH Ed25519 key
  import (including encrypted keys). Keys, passwords and Cloudflare Access service
  tokens use device-local Keychain storage.
- Server fingerprint pinning. Unknown or changed identities stop the handshake
  before authentication and show the fingerprint for independent verification.
- Existing `herdroid://add-host` links and `wooloo://add-host`, pasted links,
  camera QR scanning and QR images. Imports fill an editor and never auto-connect.
- Herdr snapshots, event invalidation, space/tab creation, space rename/close,
  pane split/zoom/close and multiline agent prompts.
- SwiftTerm terminal rendering, native keyboard input, extra keys, explicit
  watch/control/takeover, release, resize and bounded NDJSON records.
- Local agent state notifications while connected, with tap-to-open navigation.
- Offline third-party notices, privacy disclosure and iOS privacy manifest.

The Android implementation at `../herdroid` and macOS app at `../wooloo` informed
this implementation. They were not modified. The [Astra implementation
plan](docs/implementation-plan.md) and [phase status](docs/phase-status.md) distinguish
implemented code from acceptance checks still needed for release.

## Build without a paid Apple Developer account

Use Xcode 26+ with an iOS SDK and Swift 6.2+ (transitive packages may require newer
Swift versions; see the lockfile). The deployment target is iOS 17. A paid Apple
Developer membership is **not needed for simulator development**.

1. Open `WoolooMobile.xcodeproj` and select the `WoolooMobile` scheme.
2. Choose an installed iPhone/iPad simulator and Run. No signing team is needed.
3. Tap **Try the demo machine**. No server, account or SSH credentials are needed.

For a physical device, select your own development team in Signing & Capabilities.
A personal Apple ID can be used for limited personal development; TestFlight/App
Store distribution requires the appropriate Apple Developer membership. No team ID,
provisioning profile, certificate or paid capability is embedded in this project.

```sh
swift test
xcodebuild -project WoolooMobile.xcodeproj -scheme WoolooMobile \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The committed Xcode project can be regenerated with
`python3 scripts/generate-project.py`. Dependencies are pinned in `Package.resolved`
and the Xcode workspace lockfile; the patched Citadel library is vendored at a documented revision. The first build needs GitHub access.

## Connect a real machine

1. Run Herdr on your computer. The mobile protocols follow Android's Herdr
   0.9.5/protocol 22 reference; live compatibility still needs the checks below.
2. In Settings, copy the device's public SSH key. Authorize that public key using
   Wooloo on your Mac → Remote Access, or the server's normal `authorized_keys`
   procedure. The private key stays on the phone.
3. Add a machine manually or import Wooloo's Remote Access QR/link. Review its
   host, username, session and server fingerprints. Choose the device key or enter
   a password. An empty password on Save selects device-key authentication.
4. For Cloudflare, choose **Cloudflare Tunnel** and enter only its hostname.
   Access-protected hosts also need both service-token fields. Both empty on Save
   clears a previous token. The WebSocket uses TLS and port 443; SSH identity is
   still checked inside the tunnel.
5. Save the reviewed profile and open the machine. If no fingerprint was supplied,
   connection stops and displays one: independently verify it, then edit the
   machine and add the approved `SHA256:…` fingerprint before retrying.
6. Open a space/pane. **Watch** is read-only; **Control** asks for ordinary control.
   If another client owns the terminal, use the separate, confirmed **Take control**
   action. Reconnection never steals control automatically.

Direct SSH requires a reachable address or VPN. QR import does not establish a
network route or grant SSH access. Quick tunnel hostnames can change on restart.

## iOS lifecycle and preview limits

Connections close when the app goes into the background and reconnect when it
returns; Herdr keeps the agents running remotely. Local notifications only cover
state transitions observed while connected. Persistent background SSH and server
push notifications are not included.

This preview uses a single active machine connection. Advanced Android features
including quota access, image uploads, native remote scrollback gestures, terminal
mouse bridging, full tab/pane rename UI and multi-machine simultaneous connections
remain follow-up work. The terminal's local scrollback is not Herdr's remote history.
No provider credentials are read and no unofficial quota endpoints are contacted.

Before distributing: complete real Herdr and Cloudflare tests, camera/device
Keychain checks, VoiceOver/Dynamic Type and iPad visual QA, background/network
recovery checks, App Store privacy/export declarations, signing and TestFlight.
See [validation](docs/validation.md).

## Privacy and license

The app has no analytics or telemetry. It connects to the SSH machines/tunnel hosts
you review. Profile JSON contains connection metadata and trusted fingerprints;
credentials are kept separately in Keychain, accessible only while unlocked and
not synchronized to iCloud. Terminal output cannot automatically open URLs or read
or write the clipboard. Notification text may show agent task titles according to
your system notification settings.

Code and the reused Wooloo icon are MIT licensed. See [LICENSE](LICENSE) and
[third-party notices](THIRD_PARTY_NOTICES.md). Provider names indicate interoperability,
not endorsement. Report sanitized bugs through this repository's Issues; do not
include credentials or private terminal output.
