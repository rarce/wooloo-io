import Foundation

public enum ConnectionLink {
    public static func parse(_ text: String) throws -> Machine {
        guard text.utf8.count <= 16_384,
              let url = URLComponents(string: text),
              ["herdroid", "wooloo"].contains(url.scheme?.lowercased() ?? ""),
              url.host == "add-host" else { throw WoolooError.message("Use a wooloo Remote Access machine link (herdroid://add-host).") }
        let items = url.queryItems ?? []
        func value(_ name: String) throws -> String? {
            let matches = items.filter { $0.name == name }
            guard matches.count <= 1 else { throw WoolooError.message("Duplicate connection field: \(name)") }
            return matches.first?.value
        }
        var machine = Machine()
        machine.host = try value("host") ?? ""
        machine.name = try value("label") ?? machine.host
        machine.user = try value("user") ?? ""
        machine.session = try value("session") ?? "wooloo"
        machine.herdrPath = try value("herdr") ?? ""
        machine.transport = try value("transport") ?? "ssh"
        if let port = try value("port") {
            guard let parsed = Int(port), (1...65535).contains(parsed) else { throw WoolooError.message("Invalid SSH port.") }
            machine.port = parsed
        }
        machine.fingerprints = items.filter { $0.name == "fp" }.compactMap(\.value)
        guard machine.fingerprints.allSatisfy({ $0.hasPrefix("SHA256:") && Data(base64Encoded: String($0.dropFirst(7)) + String(repeating: "=", count: (4 - ($0.count - 7) % 4) % 4))?.count == 32 }) else {
            throw WoolooError.message("Invalid SSH host fingerprint.")
        }
        guard !machine.host.isEmpty, !machine.user.isEmpty else { throw WoolooError.message("The machine link needs a host and username.") }
        return machine
    }
}

public enum RemoteCommand {
    public static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
    public static func herdr(_ machine: Machine, _ args: [String]) -> String {
        let arguments = (["--session", machine.session] + args).map(quote).joined(separator: " ")
        let custom: String
        if machine.herdrPath.hasPrefix("~/") {
            custom = "\"$HOME\"/" + quote(String(machine.herdrPath.dropFirst(2))) + " "
        } else { custom = machine.herdrPath.isEmpty ? "" : quote(machine.herdrPath) + " " }
        let script = "for c in \(custom)\"$(command -v herdr 2>/dev/null)\" \"$HOME/.local/bin/herdr\" \"$HOME/.cargo/bin/herdr\" /opt/homebrew/bin/herdr /usr/local/bin/herdr /usr/bin/herdr; do if [ -n \"$c\" ] && [ -x \"$c\" ]; then exec \"$c\" \(arguments); fi; done; echo 'wooloo: herdr executable not found' >&2; exit 127"
        return "/bin/sh -c " + quote(script)
    }
}

/// Bytes are buffered until a full record is available, preserving split UTF-8 scalars.
public struct NDJSONBuffer {
    private var buffer = Data()
    public let limit: Int
    public init(limit: Int = 4 * 1024 * 1024) { self.limit = limit }
    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let index = buffer.firstIndex(of: 10) {
            guard index <= limit else { throw WoolooError.message("Remote record exceeds the size limit.") }
            let line = buffer.prefix(upTo: index)
            if !line.isEmpty { lines.append(Data(line)) }
            buffer.removeSubrange(...index)
        }
        guard buffer.count <= limit else { throw WoolooError.message("Remote record exceeds the size limit.") }
        return lines
    }
}

public struct TerminalFrame: Decodable {
    public let type: String
    public let seq: Int?
    public let width: Int?
    public let height: Int?
    public let full: Bool?
    public let bytes: String?
    public let reason: String?
    public func validatedBytes() throws -> Data {
        guard type == "terminal.frame", let width, let height,
              (1...512).contains(width), (1...512).contains(height), width * height <= 65_536,
              let bytes, bytes.count <= 1_398_104, let data = Data(base64Encoded: bytes), data.count <= 1_048_576 else {
            throw WoolooError.message("Invalid terminal frame.")
        }
        return data
    }
}
