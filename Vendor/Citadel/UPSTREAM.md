# Vendored Citadel

Source: https://github.com/orlandos-nl/Citadel
Revision: ae8562f895de06ccb86fdb1cbb65fd99c8976e12
License: MIT (LICENSE retained).

Only the two library source targets are included. The manifest omits upstream
examples, tests and their unused ColorizeSwift dependency.

Local patch: `SSHClientSession.addHandlers` hops to the channel event loop when
entered off-loop. Upstream public `SSHClient.connect(on:settings:)` calls this
synchronous pipeline API from an async Swift executor, which trips NIO's event-loop
precondition. The patch is needed by the Cloudflare socket-pair transport and the
shared bounded handshake implementation. Regression coverage is in
`Tests/WoolooCoreTests/SSHIntegrationTests.swift`.

Second patch: bidirectional TTY/PTY/exec cleanup tolerates `ChannelError.alreadyClosed`
and preserves the original error if cleanup also fails. A one-request Herdr bridge
can close immediately after its response, which otherwise turns a successful API
request into an `Already closed` failure. The real SSH exec fixture covers this race.
