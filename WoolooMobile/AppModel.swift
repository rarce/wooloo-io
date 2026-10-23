import SwiftUI
import WoolooCore
import Network

@MainActor @Observable final class AppModel {
    var machines: [Machine] = []
    var snapshot: Snapshot?
    var selectedMachine: Machine?
    var client: HerdrClient?
    var state = "Disconnected"
    var error: String?
    var untrustedFingerprint: String?
    var demo = false
    var notificationPaneID: String?
    var isConnecting = false
    var refreshTask: Task<Void, Never>?
    var foreground = true
    private var recoveryTask: Task<Void, Never>?
    private let networkMonitor = NWPathMonitor()
    private var generation = UUID()
    private var refreshing = false
    private var lastRefresh = Date.distantPast
    private let profilesURL: URL
    init() {
        profilesURL = URL.applicationSupportDirectory.appending(path: "WoolooMobile/machines.json")
        do {
            if FileManager.default.fileExists(atPath: profilesURL.path) {
                machines = try JSONDecoder().decode([Machine].self, from: Data(contentsOf: profilesURL))
            }
        } catch { self.error = "Could not load saved machines: \(error.localizedDescription)" }
        networkMonitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor in
                guard let self, self.foreground, self.client == nil, !self.demo, !self.isConnecting, self.selectedMachine != nil else { return }
                self.scheduleReconnect()
            } }
        }
        networkMonitor.start(queue: DispatchQueue(label: "dev.wooloo.mobile.network"))
    }
    func save(_ machine: Machine) {
        var updated = machines
        if let index = updated.firstIndex(where: { $0.id == machine.id }) { updated[index] = machine }
        else { updated.append(machine) }
        do {
            try FileManager.default.createDirectory(at: profilesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: profilesURL, options: [.atomic, .completeFileProtection])
            machines = updated
        } catch { self.error = "Could not save machine: \(error.localizedDescription)" }
    }
    func remove(_ machine: Machine) {
        do {
            try SecretStore.delete("password-\(machine.id)")
            try SecretStore.delete("access-id-\(machine.id)")
            try SecretStore.delete("access-secret-\(machine.id)")
            let updated = machines.filter { $0.id != machine.id }
            try JSONEncoder().encode(updated).write(to: profilesURL, options: [.atomic, .completeFileProtection])
            machines = updated
            if selectedMachine?.id == machine.id { disconnect(); selectedMachine = nil; snapshot = nil }
        } catch { self.error = error.localizedDescription }
    }
    func showDemo() {
        disconnect()
        demo = true
        snapshot = .demo
        state = "Local demo"
    }
    func disconnect(cancelRecovery: Bool = true) {
        if cancelRecovery { recoveryTask?.cancel(); recoveryTask = nil }
        generation = UUID()
        refreshTask?.cancel(); refreshTask = nil
        let previous = client
        client = nil
        Task { await previous?.close() }
        state = "Disconnected · cached state"
        demo = false
        isConnecting = false
    }
    func connect(_ machine: Machine, automatic: Bool = false) async {
        disconnect(cancelRecovery: !automatic)
        let token = generation
        if selectedMachine?.id != machine.id { snapshot = nil }
        selectedMachine = machine
        isConnecting = true
        state = "Connecting…"
        untrustedFingerprint = nil
        do {
            let password = try SecretStore.read("password-\(machine.id)").map { String(decoding: $0, as: UTF8.self) }
            let accessID = try SecretStore.read("access-id-\(machine.id)").map { String(decoding: $0, as: UTF8.self) }
            let accessSecret = try SecretStore.read("access-secret-\(machine.id)").map { String(decoding: $0, as: UTF8.self) }
            let connection = try await HerdrClient.connect(machine, password: password, accessClientID: accessID, accessSecret: accessSecret)
            guard generation == token else { await connection.close(); return }
            client = connection
            snapshot = try await connection.snapshot()
            guard generation == token else { await connection.close(); return }
            state = "Connected"
            isConnecting = false
            startObservation(connection, token: token)
        } catch {
            guard generation == token else { return }
            state = "Disconnected · cached state"
            if case WoolooError.untrustedHost(let fingerprint) = error {
                untrustedFingerprint = fingerprint
                self.error = machine.fingerprints.isEmpty ? error.localizedDescription : "SERVER IDENTITY CHANGED. Do not reuse credentials until the new fingerprint is independently verified: \(fingerprint)"
            } else if !automatic { self.error = error.localizedDescription }
            isConnecting = false
            await client?.close(); client = nil
        }
    }
    private func startObservation(_ connection: HerdrClient, token: UUID) {
        refreshTask?.cancel()
        let paneIDs = snapshot?.panes.map(\.id) ?? []
        refreshTask = Task { [weak self] in
            let safetyPoll = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                    await self?.refresh()
                }
            }
            defer { safetyPoll.cancel() }
            while !Task.isCancelled {
                guard let self, self.generation == token else { return }
                do { try await connection.subscribe(paneIDs: paneIDs) { [weak self] in await self?.refresh() } }
                catch {
                    if Task.isCancelled { return }
                    await self.refresh()
                    if self.client == nil { return }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }
    func refresh() async {
        guard !refreshing, let client, !demo else { return }
        refreshing = true
        defer { refreshing = false }
        let token = generation
        // Bound event bursts while retaining periodic authoritative refresh.
        if Date().timeIntervalSince(lastRefresh) < 0.25 { try? await Task.sleep(for: .milliseconds(250)) }
        do {
            let next = try await client.snapshot()
            guard token == generation else { return }
            let previous = snapshot
            let panesChanged = Set(previous?.panes.map(\.id) ?? []) != Set(next.panes.map(\.id))
            snapshot = next; lastRefresh = Date(); state = "Connected"
            if panesChanged { startObservation(client, token: token) }
            await AgentNotifications.shared.reconcile(previous: previous, next: next)
        } catch {
            guard token == generation else { return }
            self.error = error.localizedDescription
            disconnect()
            scheduleReconnect()
        }
    }
    private func scheduleReconnect() {
        guard foreground, !demo, let machine = selectedMachine else { return }
        recoveryTask?.cancel()
        recoveryTask = Task {
            for delay in [1, 2, 4, 8, 16, 30] {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard foreground, !demo, client == nil, !isConnecting else { return }
                await connect(machine, automatic: true)
                if client != nil { return }
            }
            state = "Disconnected · tap Reconnect to retry"
        }
    }
    func action(_ method: String, params: [String: String]) async {
        guard !demo else { error = "This is a local demo. Connect a machine to change a real session."; return }
        guard let client else { error = "Reconnect before sending commands."; return }
        do { _ = try await client.request(method, params: params); await refresh() }
        catch { self.error = error.localizedDescription }
    }
}
