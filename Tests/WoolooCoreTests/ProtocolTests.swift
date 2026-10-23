import XCTest
@testable import WoolooCore

final class ProtocolTests: XCTestCase {
    func testSnapshotPreservesServerOrderAndGeometry() throws {
        let snapshot = Snapshot.demo
        XCTAssertEqual(snapshot.workspaces.map(\.id), ["api", "web", "infra"])
        XCTAssertEqual(snapshot.panes(in: "api").map(\.id), ["p1", "p2"])
        XCTAssertEqual(snapshot.layouts?.first?.panes.last?.rect.x, 50)
        XCTAssertEqual(snapshot.panes.first?.agentStatus, .blocked)
    }
    func testUnknownStatusIsForwardCompatible() throws {
        XCTAssertEqual(try JSONDecoder().decode(AgentStatus.self, from: Data("\"future-state\"".utf8)), .unknown)
    }
    func testConnectionLinkPreservesPlusAndRepeatedPins() throws {
        let pin = "SHA256:" + Data(repeating: 251, count: 32).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let machine = try ConnectionLink.parse("herdroid://add-host?host=server.example&user=dev&port=2222&session=work&fp=\(pin)&fp=\(pin)")
        XCTAssertEqual(machine.port, 2222)
        XCTAssertEqual(machine.fingerprints, [pin, pin])
        XCTAssertEqual(machine.session, "work")
    }
    func testRejectsMalformedAndAmbiguousMachineLinks() {
        for link in ["https://example.com", "herdroid://add-host?host=a&host=b&user=c", "herdroid://add-host?host=a&user=c&port=0", "herdroid://add-host?host=a&user=c&fp=SHA256:bad"] {
            XCTAssertThrowsError(try ConnectionLink.parse(link), link)
        }
    }
    func testCloudflareLinkRetainsTransport() throws {
        let machine = try ConnectionLink.parse("herdroid://add-host?host=tunnel.example&user=dev&transport=cloudflare")
        XCTAssertEqual(machine.transport, "cloudflare")
        XCTAssertNoThrow(try machine.validate())
    }
    func testNDJSONPreservesSplitUTF8AndMultipleRecords() throws {
        var buffer = NDJSONBuffer(limit: 100)
        let data = Data("{\"text\":\"🐑\"}\n{\"done\":true}\n".utf8)
        var output: [Data] = []
        for byte in data { output += try buffer.append(Data([byte])) }
        XCTAssertEqual(output.count, 2)
        XCTAssertEqual(String(decoding: output[0], as: UTF8.self), "{\"text\":\"🐑\"}")
    }
    func testNDJSONRejectsOversizedCompleteAndIncompleteRecords() throws {
        var buffer = NDJSONBuffer(limit: 4)
        XCTAssertThrowsError(try buffer.append(Data("12345".utf8)))
        buffer = NDJSONBuffer(limit: 4)
        XCTAssertThrowsError(try buffer.append(Data("12345\n".utf8)))
    }
    func testTerminalFramesAreBounded() throws {
        let valid = try JSONDecoder().decode(TerminalFrame.self, from: Data(#"{"type":"terminal.frame","width":80,"height":24,"bytes":"aGk="}"#.utf8))
        XCTAssertEqual(try valid.validatedBytes(), Data("hi".utf8))
        for (width, height) in [(0,24), (513,24), (512,512)] {
            let json = "{\"type\":\"terminal.frame\",\"width\":\(width),\"height\":\(height),\"bytes\":\"aGk=\"}"
            let frame = try JSONDecoder().decode(TerminalFrame.self, from: Data(json.utf8))
            XCTAssertThrowsError(try frame.validatedBytes())
        }
    }
    func testShellQuoteCannotEscapeAnArgument() throws {
        let text = "a'; echo INJECTED; $(touch /tmp/unwanted)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf %s " + RemoteCommand.quote(text)]
        let output = Pipe(); process.standardOutput = output
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), text)
    }
    func testProfileJSONContainsNoCredentials() throws {
        var machine = Machine(); machine.host = "example.com"; machine.user = "dev"
        let json = String(decoding: try JSONEncoder().encode(machine), as: UTF8.self)
        XCTAssertFalse(json.contains("password")); XCTAssertFalse(json.contains("privateKey"))
    }
}
