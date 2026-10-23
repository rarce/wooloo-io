import SwiftUI
import WoolooCore
import SwiftTerm

@MainActor @Observable final class TerminalModel {
    var message = "Opening terminal…"
    var connected = false
    var cols = 80
    var rows = 24
    var render: ((Data, Int?, Int?) -> Void)?
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<Data>.Continuation?
    private var lastSequence: Int?
    private var generation = UUID()
    func open(client: HerdrClient?, pane: String, demo: Bool, takeover: Bool = false) {
        stop()
        lastSequence = nil
        let token = generation
        if demo {
            connected = true
            message = "Local demo · simulated control"
            render?(Data("\u{1b}[2J\u{1b}[H\u{1b}[36mWooloo Mobile · demo\u{1b}[0m\r\n\r\nClaude Code  •  api\r\n\r\nMigration is ready for review.\r\n\r\n  1. Approve migration\r\n  2. Explain the changes\r\n  3. Cancel\r\n\r\nThis terminal runs locally. No commands reach a server.\r\n".utf8), nil, nil)
            return
        }
        guard let client else { message = "Reconnect to your machine before opening a terminal."; return }
        let pair = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(64))
        continuation = pair.continuation
        message = "Opening terminal…"
        task = Task {
            do {
                try await client.terminal(pane: pane, cols: cols, rows: rows, observe: false, takeover: takeover, commands: pair.stream) { [weak self] frame in
                    let bytes = try frame.validatedBytes()
                    try await self?.receive(frame, data: bytes, token: token)
                }
                if !Task.isCancelled, token == self.generation { self.message = "Terminal stream ended. Reopen to continue." }
            } catch {
                if !Task.isCancelled, token == self.generation { self.message = error.localizedDescription }
            }
            if !Task.isCancelled, token == self.generation { self.connected = false }
        }
    }
    private func receive(_ frame: TerminalFrame, data: Data, token: UUID) throws {
        guard token == generation else { return }
        if let seq = frame.seq, let previous = lastSequence, seq <= previous { throw WoolooError.message("Terminal frames arrived out of order. Reopen the terminal.") }
        lastSequence = frame.seq
        connected = true
        message = "You have control"
        render?(data, frame.width, frame.height)
    }
    func send(_ object: [String: Any]) {
        guard connected, let continuation else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            guard data.count <= 65_536 else { throw WoolooError.message("Input is too large. Send a smaller chunk.") }
            if case .dropped = continuation.yield(data) { stop(); message = "Terminal input queue full. Reopen before typing again." }
        } catch { message = error.localizedDescription }
    }
    func input(_ data: Data) { send(["type": "terminal.input", "bytes": data.base64EncodedString()]) }
    func resize(cols: Int, rows: Int) {
        self.cols = max(1, min(512, cols)); self.rows = max(1, min(512, rows))
        send(["type": "terminal.resize", "cols": self.cols, "rows": self.rows])
    }
    func stop() {
        generation = UUID()
        if let continuation {
            if let release = try? JSONSerialization.data(withJSONObject: ["type": "terminal.release"]) { continuation.yield(release) }
        }
        continuation?.finish(); continuation = nil
        let oldTask = task
        // Allow the release record to flush before cancelling the exec reader.
        Task { try? await Task.sleep(for: .milliseconds(150)); oldTask?.cancel() }
        task = nil; connected = false
    }
}

struct TerminalSurface: UIViewRepresentable {
    let model: TerminalModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero, font: .monospacedSystemFont(ofSize: 13, weight: .regular))
        view.nativeBackgroundColor = UIColor(red: 0.035, green: 0.045, blue: 0.06, alpha: 1)
        view.nativeForegroundColor = .init(white: 0.9, alpha: 1)
        view.terminalDelegate = context.coordinator
        model.render = { [weak view] data, width, height in
            guard let view else { return }
            if let width, let height { view.resize(cols: width, rows: height) }
            view.feed(byteArray: Array(data)[...])
        }
        return view
    }
    func updateUIView(_ view: TerminalView, context: Context) {
        view.isUserInteractionEnabled = model.connected
        if model.connected && !context.coordinator.wasConnected {
            _ = view.becomeFirstResponder()
        }
        context.coordinator.wasConnected = model.connected
    }
    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) { coordinator.model.render = nil }
    @MainActor final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        let model: TerminalModel
        var wasConnected = false
        init(_ model: TerminalModel) { self.model = model }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { model.resize(cols: newCols, rows: newRows) }
        func send(source: TerminalView, data: ArraySlice<UInt8>) { model.input(Data(data)) }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            // Remote output cannot silently open arbitrary URL schemes.
        }
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

struct PaneView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var phase
    let pane: Pane
    @State private var terminal = TerminalModel()
    @State private var takeover = false
    @State private var closePane = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                StateBadge(state: pane.agentStatus ?? .unknown)
                Spacer()
                Text(app.demo ? "LOCAL DEMO" : app.state).font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal).padding(.vertical, 8)
            TerminalSurface(model: terminal)
                .accessibilityLabel("Terminal for \(pane.displayTitle)")
                .onAppear { openTerminal() }
            if !terminal.connected {
                Text(terminal.message)
                    .font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.vertical, 8)
            }
        }
        .navigationTitle(pane.displayAgent ?? pane.agent ?? "Terminal").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                if !terminal.connected {
                    Button("Reconnect terminal") { openTerminal() }
                }
                Button("Take control from another client", role: .destructive) { takeover = true }
                Divider()
                Button("Split right") { Task { await app.action("pane.split", params: ["target_pane_id": pane.id, "direction": "right"]) } }
                Button("Split down") { Task { await app.action("pane.split", params: ["target_pane_id": pane.id, "direction": "down"]) } }
                Button("Toggle zoom") { Task { await app.action("pane.zoom", params: ["pane_id": pane.id, "mode": "toggle"]) } }
                Button("Close pane", role: .destructive) { closePane = true }
            } label: { Image(systemName: "rectangle.split.2x1") }.disabled(app.demo || app.client == nil)
        }
        .onDisappear { terminal.stop() }
        .onChange(of: phase) { _, value in
            if value == .active { openTerminal() } else { terminal.stop() }
        }
        .onChange(of: app.client.map { ObjectIdentifier($0) }) { _, _ in
            guard phase == .active else { return }
            openTerminal()
        }
        .confirmationDialog("Take control from the current client?", isPresented: $takeover, titleVisibility: .visible) {
            Button("Take control", role: .destructive) { openTerminal(takeover: true) }
        }
        .confirmationDialog("Close this pane and its running process?", isPresented: $closePane, titleVisibility: .visible) {
            Button("Close pane", role: .destructive) { terminal.stop(); Task { await app.action("pane.close", params: ["pane_id": pane.id]) } }
        }
    }
    private func openTerminal(takeover: Bool = false) {
        terminal.open(client: app.client, pane: pane.id, demo: app.demo, takeover: takeover)
    }

}
