import Foundation

public enum AgentStatus: String, Codable, Sendable, CaseIterable {
    case idle, working, blocked, done, unknown
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public struct Machine: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name = ""
    public var host = ""
    public var port = 22
    public var user = ""
    public var session = "wooloo"
    public var herdrPath = ""
    public var fingerprints: [String] = []
    public var transport = "ssh"
    public init() {}
    public func validate() throws {
        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace }), !user.isEmpty,
              (1...65535).contains(port), !session.isEmpty else {
            throw WoolooError.message("Enter a hostname, SSH username, port (1–65535) and session.")
        }
        guard ["ssh", "cloudflare"].contains(transport) else { throw WoolooError.message("Unsupported connection transport.") }
    }
}

public struct Workspace: Decodable, Identifiable, Sendable {
    public let workspaceId: String
    public var id: String { workspaceId }
    public let label: String
    public let focused: Bool?
    public let activeTabId: String?
    public let agentStatus: AgentStatus?
}
public struct HerdrTab: Decodable, Identifiable, Sendable {
    public let tabId: String
    public var id: String { tabId }
    public let workspaceId: String
    public let label: String
    public let focused: Bool?
}
public struct Pane: Decodable, Identifiable, Sendable {
    public let paneId: String
    public var id: String { paneId }
    public let workspaceId: String
    public let tabId: String
    public let title: String?
    public let label: String?
    public let displayAgent: String?
    public let agent: String?
    public let cwd: String?
    public let agentStatus: AgentStatus?
    public let focused: Bool?
    public var displayTitle: String { [title, label, displayAgent, agent, cwd].compactMap { $0 }.first(where: { !$0.isEmpty }) ?? paneId }
}
public struct PaneRect: Decodable, Sendable { public let x, y, width, height: Int }
public struct LayoutPane: Decodable, Sendable { public let paneId: String; public let rect: PaneRect }
public struct PaneLayout: Decodable, Sendable {
    public let tabId: String
    public let area: PaneRect
    public let panes: [LayoutPane]
}
public struct Snapshot: Decodable, Sendable {
    public let version: String?
    public let workspaces: [Workspace]
    public let tabs: [HerdrTab]
    public let panes: [Pane]
    public let layouts: [PaneLayout]?
    public static func decode(_ data: Data) throws -> Snapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
    public func panes(in workspace: String) -> [Pane] { panes.filter { $0.workspaceId == workspace } }
    public static var demo: Snapshot {
        try! decode(Data(demoJSON.utf8))
    }
    private static let demoJSON = #"""
    {"version":"0.9.5","workspaces":[
      {"workspace_id":"api","label":"api","focused":true,"active_tab_id":"t1","agent_status":"blocked"},
      {"workspace_id":"web","label":"web","active_tab_id":"t2","agent_status":"done"},
      {"workspace_id":"infra","label":"infra","active_tab_id":"t3","agent_status":"idle"}],
    "tabs":[{"tab_id":"t1","workspace_id":"api","label":"Development"},{"tab_id":"t2","workspace_id":"web","label":"Frontend"},{"tab_id":"t3","workspace_id":"infra","label":"Operations"}],
    "panes":[
      {"pane_id":"p1","workspace_id":"api","tab_id":"t1","display_agent":"Claude Code","title":"Review database migration","agent_status":"blocked","cwd":"~/projects/api","focused":true},
      {"pane_id":"p2","workspace_id":"api","tab_id":"t1","display_agent":"Codex","title":"Add API pagination","agent_status":"working","cwd":"~/projects/api"},
      {"pane_id":"p3","workspace_id":"web","tab_id":"t2","display_agent":"Codex","title":"Polish the dashboard","agent_status":"done","cwd":"~/projects/web"},
      {"pane_id":"p4","workspace_id":"infra","tab_id":"t3","title":"Terminal","agent_status":"idle","cwd":"~/projects/infra"}],
    "layouts":[{"tab_id":"t1","area":{"x":0,"y":0,"width":100,"height":40},"panes":[{"pane_id":"p1","rect":{"x":0,"y":0,"width":50,"height":40}},{"pane_id":"p2","rect":{"x":50,"y":0,"width":50,"height":40}}]}]}
    """#
}
public enum WoolooError: LocalizedError {
    case message(String)
    case untrustedHost(String)
    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .untrustedHost(let fingerprint): return "Verify this server fingerprint through a trusted channel before saving it: \(fingerprint)"
        }
    }
}
