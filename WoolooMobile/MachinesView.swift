import SwiftUI
import WoolooCore

extension AgentStatus {
    var color: Color {
        switch self { case .working: return .yellow; case .blocked: return .red; case .done: return .teal; case .idle: return .green; case .unknown: return .gray }
    }
}
struct StateBadge: View {
    let state: AgentStatus
    var body: some View {
        Label(state.rawValue.capitalized, systemImage: state == .working ? "circle.dotted" : state == .blocked ? "exclamationmark.circle.fill" : "circle.fill")
            .font(.caption).foregroundStyle(state.color)
    }
}
struct MachinesView: View {
    @Environment(AppModel.self) private var model
    @State private var editor: Machine?
    @State private var settings = false
    @State private var openSession = false
    @State private var deleteTarget: Machine?
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("YOUR AGENTS. ANYWHERE.").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.mint)
                        Text("Pick up where\nyou left off.").font(.largeTitle.bold())
                        Text("Your spaces and coding agents, connected directly to your machines.").foregroundStyle(.secondary)
                    }.padding(.vertical, 16).listRowBackground(Color.clear)
                }
                Section("Machines") {
                    if model.machines.isEmpty {
                        ContentUnavailableView("Your machines live here", systemImage: "desktopcomputer", description: Text("Add a machine running Herdr, or explore the local demo."))
                    }
                    ForEach(model.machines) { machine in
                        Button {
                            openSession = true
                            Task { await model.connect(machine) }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(.mint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(machine.name.isEmpty ? machine.host : machine.name).font(.headline).foregroundStyle(.primary)
                                    Text("\(machine.user)@\(machine.host) · \(machine.session)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 8)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { deleteTarget = machine }
                            Button("Edit") { editor = machine }.tint(.blue)
                        }
                    }
                    Button { editor = Machine() } label: { Label("Add machine", systemImage: "plus") }
                }
                Section {
                    Button { model.showDemo(); openSession = true } label: {
                        HStack { Label("Try the demo machine", systemImage: "play.rectangle"); Spacer(); Text("OFFLINE").font(.caption2).foregroundStyle(.secondary) }
                    }
                } footer: { Text("No Wooloo account. Your credentials stay on this device.") }
            }
            .navigationTitle("wooloo mobile")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings and SSH key") }
                ToolbarItem(placement: .topBarTrailing) { Button { editor = Machine() } label: { Image(systemName: "plus") }.accessibilityLabel("Add machine") }
            }
            .navigationDestination(isPresented: $openSession) { SpacesView() }
            .navigationDestination(item: $model.notificationPaneID) { id in
                if let pane = model.snapshot?.panes.first(where: { $0.id == id }) { PaneView(pane: pane) }
                else { ContentUnavailableView("Pane unavailable", systemImage: "terminal") }
            }
            .sheet(item: $editor) { MachineEditor(machine: $0) }
            .sheet(isPresented: $settings) { SettingsView() }
            .onOpenURL { url in
                do { editor = try ConnectionLink.parse(url.absoluteString) } catch { model.error = error.localizedDescription }
            }
            .alert("Wooloo Mobile", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                if let fingerprint = model.untrustedFingerprint {
                    Button("Copy fingerprint") { UIPasteboard.general.string = fingerprint; model.error = nil }
                }
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
            .confirmationDialog("Delete this machine and its saved password?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
                Button("Delete machine", role: .destructive) { if let target = deleteTarget { model.remove(target) }; deleteTarget = nil }
            }
        }
    }
}
