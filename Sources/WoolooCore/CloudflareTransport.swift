import Foundation
import Darwin
import NIO
import NIOSSH
import Citadel

/// Reject redirects so Access headers can only be sent to the reviewed hostname.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// A bounded, backpressured byte bridge. The socket pair is device-local; no TCP port is opened.
/// URLSession handles TLS and WebSocket framing, while NIO/Citadel owns the SSH protocol.
final class CloudflareTransport: @unchecked Sendable {
    let channel: Channel
    private let socket: URLSessionWebSocketTask
    private let session: URLSession
    private let peer: Int32
    private let lock = NSLock()
    private var closed = false
    private var reader: Task<Void, Never>?
    private var writer: Task<Void, Never>?
    private var ping: Task<Void, Never>?
    private init(channel: Channel, socket: URLSessionWebSocketTask, session: URLSession, peer: Int32) {
        self.channel = channel; self.socket = socket; self.session = session; self.peer = peer
    }
    static func open(host: String, clientID: String?, secret: String?, group: EventLoopGroup) async throws -> CloudflareTransport {
        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace || "/:@?#".contains($0) }),
              let url = URL(string: "wss://\(host)/") else { throw WoolooError.message("Invalid Cloudflare hostname.") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        if let clientID, let secret, !clientID.isEmpty, !secret.isEmpty {
            guard !clientID.contains(where: { $0.isNewline }), !secret.contains(where: { $0.isNewline }) else { throw WoolooError.message("Invalid Cloudflare Access token.") }
            request.setValue(clientID, forHTTPHeaderField: "CF-Access-Client-Id")
            request.setValue(secret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = 1024 * 1024
        var descriptors: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { session.invalidateAndCancel(); throw WoolooError.message("Could not create the local SSH transport.") }
        var noSignal: Int32 = 1
        setsockopt(descriptors[1], SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        let channel: Channel
        do {
            channel = try await ClientBootstrap(group: group).channelOption(ChannelOptions.autoRead, value: false).withConnectedSocket(descriptors[0]).get()
        } catch {
            Darwin.close(descriptors[0]); Darwin.close(descriptors[1]); session.invalidateAndCancel(); throw error
        }
        let bridge = CloudflareTransport(channel: channel, socket: socket, session: session, peer: descriptors[1])
        socket.resume()
        bridge.start()
        return bridge
    }
    private func start() {
        lock.lock()
        let peer = self.peer, socket = self.socket
        writer = Task.detached { [weak self] in
            defer { self?.close() }
            var bytes = [UInt8](repeating: 0, count: 64 * 1024)
            do {
                while !Task.isCancelled {
                    let count = Darwin.read(peer, &bytes, bytes.count)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { return }
                    try await socket.send(.data(Data(bytes.prefix(count))))
                }
            } catch { return }
        }
        reader = Task.detached { [weak self] in
            defer { self?.close() }
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard case .data(let data) = message, data.count <= 1024 * 1024 else { return }
                    try data.withUnsafeBytes { raw in
                        var offset = 0
                        while offset < raw.count {
                            let count = Darwin.write(peer, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                            if count < 0 && errno == EINTR { continue }
                            guard count > 0 else { throw WoolooError.message("Cloudflare transport closed.") }
                            offset += count
                        }
                    }
                }
            } catch { return }
        }
        ping = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(20))
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        socket.sendPing { error in
                            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                        }
                    }
                }
            } catch { self?.close() }
        }
        lock.unlock()
        channel.closeFuture.whenComplete { [weak self] _ in self?.close() }
    }
    func close() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        let reader = reader, writer = writer, ping = ping
        lock.unlock()
        shutdown(peer, SHUT_RDWR)
        socket.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
        reader?.cancel(); writer?.cancel(); ping?.cancel()
        channel.close(promise: nil)
        let peer = self.peer
        Task.detached {
            await reader?.value; await writer?.value
            Darwin.close(peer)
        }
    }
}
