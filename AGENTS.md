# Wooloo Mobile for iOS

Native SwiftUI iOS 17+ companion to Herdr. The product name is **Wooloo Mobile**;
repository name is `wooloo-io` as requested. Android `../herdroid` is the mobile
protocol reference; macOS `../wooloo` uses a different terminal protocol.

- `Sources/WoolooCore`: models, links, SSH/Cloudflare, Keychain, Herdr NDJSON.
- `WoolooMobile`: SwiftUI screens, UIKit SwiftTerm terminal, QR and notifications.
- `Tests/WoolooCoreTests`: protocol/security and isolated real SSH tests.
- Regenerate the committed Xcode project after adding app source files:
  `python3 scripts/generate-project.py` (no XcodeGen installation required).
- Validate using `swift test`, then the simulator build in README.
- Preserve server ordering. Events invalidate snapshots; terminal ANSI deltas must
  be processed in order, never dropped/coalesced.
- Never put private keys, passwords or Access tokens in profiles, logs or fixtures.
  Enforce host pins before authentication. Review destination changes.
- Never run integration tests against a primary Herdr session. Use isolated
  fixtures; mock credentials in tests have no access to a real account.
- No automatic takeover, destructive pane closure, or remote key authorization.
- Keep release status candid: host-side tests are not physical-device validation.
