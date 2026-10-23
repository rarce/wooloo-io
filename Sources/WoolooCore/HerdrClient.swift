import Foundation
import Citadel
import Crypto
import NIO
import NIOSSH

final class HostValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let pins: [String]
    init(pins: [String]) { self.pins = pins }
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let line = String(openSSHPublicKey: hostKey)
        let parts = line.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else {
            validationCompletePromise.fail(WoolooError.message("Cannot decode server identity.")); return
        }
        let fingerprint = "SHA256:" + Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
        if pins.contains(fingerprint) { validationCompletePromise.succeed(()) }
        else { validationCompletePromise.fail(WoolooError.untrustedHost(fingerprint)) }
    }
}

/// One multiplexed SSH connection. Every API call uses its own bidirectional exec channel.
public actor HerdrClient {
    private let machine: Machine
    private let ssh: SSHClient
    private let tunnel: CloudflareTransport?
    private var nextID = 0
    private var activeRequests = 0
    init(machine: Machine, ssh: SSHClient, tunnel: CloudflareTransport? = nil) { self.machine = machine; self.ssh = ssh; self.tunnel = tunnel }
    public static func connect(_ machine: Machine, password: String?, accessClientID: String? = nil, accessSecret: String? = nil) async throws -> HerdrClient {
        try machine.validate()
        let key = try SecretStore.deviceKey()
        var settings = SSHClientSettings(host: machine.host, port: machine.port, authenticationMethod: {
            if let password, !password.isEmpty { return .passwordBased(username: machine.user, password: password) }
            return .ed25519(username: machine.user, privateKey: key)
        }, hostKeyValidator: .custom(HostValidator(pins: machine.fingerprints)))
        settings.connectTimeout = .seconds(20)
        if machine.transport == "cloudflare" {
            let tunnel = try await CloudflareTransport.open(host: machine.host, clientID: accessClientID, secret: accessSecret, group: settings.group)
            do {
                let client = try await connectChannel(tunnel.channel, settings: settings)
                return HerdrClient(machine: machine, ssh: client, tunnel: tunnel)
            } catch { tunnel.close(); throw error }
        }
        // Disable reads until Citadel has installed its SSH handlers, so no server banner is lost.
        let channel = try await ClientBootstrap(group: settings.group).channelOption(ChannelOptions.autoRead, value: false).connectTimeout(.seconds(20)).connect(host: machine.host, port: machine.port).get()
        do { return try await HerdrClient(machine: machine, ssh: connectChannel(channel, settings: settings)) }
        catch { try? await channel.close(); throw error }
    }
    static func connectChannel(_ channel: Channel, settings: SSHClientSettings) async throws -> SSHClient {
        let readEnabler = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                if (try? await channel.pipeline.handler(type: NIOSSHHandler.self).map { _ in true }.get()) == true {
                    try? await channel.setOption(ChannelOptions.autoRead, value: true).get()
                    return
                }
            }
        }
        defer { readEnabler.cancel() }
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: SSHClient.self) { group in
                group.addTask { try await SSHClient.connect(on: channel, settings: settings) }
                group.addTask {
                    try await Task.sleep(for: .seconds(20))
                    try? await channel.close()
                    throw WoolooError.message("SSH handshake timed out. Check the address, authentication and tunnel Access token.")
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } onCancel: { channel.close(promise: nil) }
    }
    public func close() async { tunnel?.close(); try? await ssh.close() }
    public func request(_ method: String, params: [String: String] = [:]) async throws -> Data {
        guard activeRequests < 4 else { throw WoolooError.message("Too many requests. Try again shortly.") }
        activeRequests += 1
        defer { activeRequests -= 1 }
        nextID += 1
        let id = "wooloo_ios_\(nextID)"
        let line = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params]) + Data([10])
        let command = RemoteCommand.herdr(machine, ["remote-api-bridge"])
        let ssh = self.ssh
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                var answer: Data?
                try await ssh.withExec(command) { inbound, writer in
                    try await writer.write(ByteBuffer(data: line))
                    var records = NDJSONBuffer()
                    var stderr = Data()
                    for try await output in inbound {
                        try Task.checkCancellation()
                        switch output {
                        case .stdout(let buffer):
                            for record in try records.append(Data(buffer.readableBytesView)) {
                                guard let envelope = try JSONSerialization.jsonObject(with: record) as? [String: Any],
                                      envelope["id"] as? String == id else { throw WoolooError.message("Invalid Herdr response ID.") }
                                if let error = envelope["error"] as? [String: Any] { throw WoolooError.message(error["message"] as? String ?? "Herdr request failed.") }
                                guard let result = envelope["result"] as? [String: Any] else { throw WoolooError.message("Missing Herdr result.") }
                                answer = try JSONSerialization.data(withJSONObject: result)
                                return
                            }
                        case .stderr(let buffer):
                            stderr.append(contentsOf: buffer.readableBytesView.prefix(max(0, 16384 - stderr.count)))
                        }
                    }
                    throw WoolooError.message(stderr.isEmpty ? "Herdr closed the connection. Check the session and server version." : String(decoding: stderr, as: UTF8.self))
                }
                guard let answer else { throw WoolooError.message("Empty Herdr response.") }
                return answer
            }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                try? await ssh.close()
                throw WoolooError.message("Herdr request timed out. Reconnect to retry.")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        } onCancel: { Task { try? await ssh.close() } }
    }
    public func snapshot() async throws -> Snapshot {
        let result = try await request("session.snapshot")
        guard let object = try JSONSerialization.jsonObject(with: result) as? [String: Any], let snapshot = object["snapshot"] else { throw WoolooError.message("Missing session snapshot.") }
        return try Snapshot.decode(JSONSerialization.data(withJSONObject: snapshot))
    }
    public func prompt(pane: String, text: String) async throws { _ = try await request("agent.prompt", params: ["target": pane, "text": text]) }
    public func sendText(pane: String, text: String) async throws { _ = try await request("pane.send_text", params: ["pane_id": pane, "text": text]) }

    public func subscribe(paneIDs: [String] = [], onChange: @escaping @Sendable () async -> Void) async throws {
        let command = RemoteCommand.herdr(machine, ["remote-api-bridge"])
        let subscriptions = ["workspace.created", "workspace.updated", "workspace.renamed", "workspace.moved", "workspace.reordered", "workspace.closed", "workspace.focused", "tab.created", "tab.closed", "tab.focused", "tab.renamed", "tab.moved", "pane.created", "pane.closed", "pane.updated", "pane.focused", "pane.moved", "pane.exited", "pane.agent_detected", "layout.updated"].map { ["type": $0] }
            + paneIDs.map { ["type": "pane.agent_status_changed", "pane_id": $0] }
        let line = try JSONSerialization.data(withJSONObject: ["id": "events", "method": "events.subscribe", "params": ["subscriptions": subscriptions]]) + Data([10])
        try await ssh.withExec(command) { inbound, writer in
            try await writer.write(ByteBuffer(data: line))
            var records = NDJSONBuffer(limit: 1024 * 1024)
            for try await output in inbound {
                try Task.checkCancellation()
                if case .stdout(let buffer) = output {
                    for record in try records.append(Data(buffer.readableBytesView)) {
                        let object = try JSONSerialization.jsonObject(with: record) as? [String: Any]
                        if object?["error"] != nil { throw WoolooError.message("Herdr event subscription failed.") }
                        await onChange()
                    }
                }
            }
        }
        throw WoolooError.message("Event stream disconnected.")
    }

    public func terminal(pane: String, cols: Int, rows: Int, observe: Bool, takeover: Bool,
                         commands: AsyncStream<Data>, onFrame: @escaping @Sendable (TerminalFrame) async throws -> Void) async throws {
        var args = ["terminal", "session", observe ? "observe" : "control", pane, "--cols", String(cols), "--rows", String(rows)]
        if takeover && !observe { args.append("--takeover") }
        let command = RemoteCommand.herdr(machine, args)
        try await ssh.withExec(command) { inbound, writer in
            let writeTask = Task {
                for await data in commands {
                    try Task.checkCancellation()
                    if !observe { try await writer.write(ByteBuffer(data: data + Data([10]))) }
                }
            }
            defer { writeTask.cancel() }
            var records = NDJSONBuffer(limit: 1_500_000)
            for try await output in inbound {
                try Task.checkCancellation()
                switch output {
                case .stdout(let buffer):
                    for record in try records.append(Data(buffer.readableBytesView)) {
                        let frame = try JSONDecoder().decode(TerminalFrame.self, from: record)
                        if frame.type == "terminal.closed" { throw WoolooError.message(frame.reason ?? "Terminal closed.") }
                        if frame.type == "terminal.frame" { _ = try frame.validatedBytes(); try await onFrame(frame) }
                    }
                case .stderr(let buffer):
                    let text = String(decoding: buffer.readableBytesView.prefix(16384), as: UTF8.self)
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw WoolooError.message(text) }
                }
            }
        }
    }
}
