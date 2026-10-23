import XCTest
import Foundation
import Darwin
import Citadel
import Crypto
import NIO
@preconcurrency import NIOSSH
@testable import WoolooCore

private final class FixtureAuth: NIOSSHServerUserAuthenticationDelegate {
    let supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods = [.password]
    func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        if case .password(let password) = request.request, password.password == "fixture-only", request.username == "fixture" { responsePromise.succeed(.success) }
        else { responsePromise.succeed(.failure) }
    }
}
private final class FixtureAPI: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData
    var data = Data()
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is SSHChannelRequestEvent.ExecRequest { context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil) }
        else { context.fireUserInboundEventTriggered(event) }
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = channelData.data else { return }
        self.data.append(contentsOf: buffer.readableBytesView)
        guard self.data.contains(10), let request = try? JSONSerialization.jsonObject(with: self.data) as? [String: Any], let id = request["id"] as? String else { return }
        let response = try! JSONSerialization.data(withJSONObject: ["id": id, "result": ["fixture": "SSH exec works"]]) + Data([10])
        context.writeAndFlush(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(ByteBuffer(data: response))))).whenComplete { _ in
            context.triggerUserOutboundEvent(SSHChannelRequestEvent.ExitStatus(exitStatus: 0), promise: nil)
            context.close(promise: nil)
        }
    }
}
final class SSHIntegrationTests: XCTestCase {
    func testRealSSHHandshakeHostPinAndExecOverLocalSocketPair() async throws {
        let fixture = try await makeFixture()
        defer { fixture.server.close(promise: nil); fixture.client.close(promise: nil) }
        let settings = SSHClientSettings(host: "fixture", authenticationMethod: { .passwordBased(username: "fixture", password: "fixture-only") }, hostKeyValidator: .custom(HostValidator(pins: [fixture.fingerprint])))
        let ssh = try await HerdrClient.connectChannel(fixture.client, settings: settings)
        let herdr = HerdrClient(machine: Machine(), ssh: ssh)
        let result = try await herdr.request("ping")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: result) as? [String: String])
        XCTAssertEqual(object["fixture"], "SSH exec works")
        await herdr.close()
    }
    func testUnknownServerIsRejectedWithFingerprintBeforeAuthentication() async throws {
        let fixture = try await makeFixture()
        defer { fixture.server.close(promise: nil); fixture.client.close(promise: nil) }
        let settings = SSHClientSettings(host: "fixture", authenticationMethod: { .passwordBased(username: "fixture", password: "fixture-only") }, hostKeyValidator: .custom(HostValidator(pins: [])))
        do { _ = try await HerdrClient.connectChannel(fixture.client, settings: settings); XCTFail("Untrusted server was accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains(fixture.fingerprint), error.localizedDescription) }
    }
    private func makeFixture() async throws -> (server: Channel, client: Channel, fingerprint: String) {
        var pair: [Int32] = [0,0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else { throw WoolooError.message("socketpair failed") }
        let group = MultiThreadedEventLoopGroup.singleton
        let key = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let line = String(openSSHPublicKey: key.publicKey)
        let blob = Data(base64Encoded: String(line.split(separator: " ")[1]))!
        let fingerprint = "SHA256:" + Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let server = try await ClientBootstrap(group: group).channelInitializer { channel in
            channel.eventLoop.makeCompletedFuture {
                try channel.pipeline.syncOperations.addHandler(NIOSSHHandler(role: .server(.init(hostKeys: [key], userAuthDelegate: FixtureAuth())), allocator: channel.allocator, inboundChildChannelInitializer: { child, _ in
                    child.eventLoop.makeCompletedFuture { try child.pipeline.syncOperations.addHandler(FixtureAPI()) }
                }))
            }
        }.withConnectedSocket(pair[0]).get()
        let client = try await ClientBootstrap(group: group).channelOption(ChannelOptions.autoRead, value: false).withConnectedSocket(pair[1]).get()
        return (server, client, fingerprint)
    }
}
