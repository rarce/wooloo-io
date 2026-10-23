import SwiftUI
import WoolooCore

struct SpacesView: View {
    @Environment(AppModel.self) private var model
    @State private var create = false
    @State private var label = ""
    @State private var cwd = ""
    var body: some View {
        List {
            Section {
                Label(model.state, systemImage: model.demo ? "play.circle" : model.client == nil ? "wifi.slash" : "checkmark.shield")
                    .font(.caption).foregroundStyle(model.client != nil || model.demo ? .mint : .orange)
                if model.isConnecting { ProgressView("Opening your session…") }
                if !model.demo, model.client == nil, !model.isConnecting, let machine = model.selectedMachine {
                    Button("Reconnect") { Task { await model.connect(machine) } }
                }
            }
            if let snapshot = model.snapshot {
                Section("Spaces · \(snapshot.workspaces.count)") {
                    ForEach(snapshot.workspaces) { workspace in
                        NavigationLink {
                            SpaceView(workspaceID: workspace.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "square.stack.3d.up").foregroundStyle((workspace.agentStatus ?? .unknown).color).font(.title2)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(workspace.label.isEmpty ? workspace.id : workspace.label).font(.headline)
                                        Text("\(snapshot.panes(in: workspace.id).count) \(snapshot.panes(in: workspace.id).count == 1 ? "pane" : "panes")").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    StateBadge(state: workspace.agentStatus ?? .unknown)
                                }
                                if let tab = workspace.activeTabId, let layout = snapshot.layouts?.first(where: { $0.tabId == tab }) {
                                    LayoutMiniature(layout: layout, panes: snapshot.panes).frame(height: 44)
                                }
                            }.padding(.vertical, 8)
                        }
                    }
                }
            } else if !model.isConnecting { ContentUnavailableView("No session yet", systemImage: "network", description: Text("Connect to a machine to see its spaces.")) }
        }
        .navigationTitle(model.demo ? "Demo machine" : model.selectedMachine?.name ?? "Spaces")
        .refreshable { await model.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { create = true } label: { Image(systemName: "plus") }.accessibilityLabel("Create space").disabled(model.demo || model.client == nil) }
        }
        .sheet(isPresented: $create) {
            NavigationStack {
                Form { TextField("Space name", text: $label); TextField("Working directory", text: $cwd).textInputAutocapitalization(.never).autocorrectionDisabled() }
                    .navigationTitle("New space")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { create = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Create") { create = false; Task { await model.action("workspace.create", params: ["label": label, "cwd": cwd]) } }.disabled(label.isEmpty) }
                    }
            }.presentationDetents([.medium])
        }
    }
}
struct LayoutMiniature: View {
    let layout: PaneLayout
    let panes: [Pane]
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(layout.panes, id: \.paneId) { entry in
                    let state = panes.first(where: { $0.id == entry.paneId })?.agentStatus ?? .unknown
                    let scaleX = geometry.size.width / CGFloat(max(1, layout.area.width))
                    let scaleY = geometry.size.height / CGFloat(max(1, layout.area.height))
                    let width = max(CGFloat(2), scaleX * CGFloat(entry.rect.width) - 3)
                    let height = max(CGFloat(2), scaleY * CGFloat(entry.rect.height) - 3)
                    let x = scaleX * CGFloat(entry.rect.x - layout.area.x)
                    let y = scaleY * CGFloat(entry.rect.y - layout.area.y)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(state.color.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(state.color.opacity(0.7), lineWidth: 1))
                        .frame(width: width, height: height)
                        .offset(x: x, y: y)
                }
            }
        }.accessibilityLabel("Pane layout, \(layout.panes.count) panes")
    }
}
struct SpaceView: View {
    @Environment(AppModel.self) private var model
    let workspaceID: String
    @State private var close = false
    @State private var rename = false
    @State private var label = ""
    private var workspace: Workspace? { model.snapshot?.workspaces.first { $0.id == workspaceID } }
    var body: some View {
        List {
            if let snapshot = model.snapshot {
                Section("Agents & terminals") {
                    ForEach(snapshot.panes(in: workspaceID)) { pane in
                        NavigationLink { PaneView(pane: pane) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                RoundedRectangle(cornerRadius: 2).fill(pane.focused == true ? Color.primary : Color.clear).frame(width: 3)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack { Text(pane.displayAgent ?? pane.agent ?? "Terminal").font(.headline); Spacer(); StateBadge(state: pane.agentStatus ?? .unknown) }
                                    Text(pane.displayTitle).font(.subheadline).foregroundStyle(.secondary)
                                    if let cwd = pane.cwd { Text(cwd).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
                                }
                            }.padding(.vertical, 8)
                        }
                    }
                }
                ForEach(snapshot.tabs.filter { $0.workspaceId == workspaceID }) { tab in
                    Section(tab.label.isEmpty ? "Tab" : tab.label) {
                        if let layout = snapshot.layouts?.first(where: { $0.tabId == tab.id }) { LayoutMiniature(layout: layout, panes: snapshot.panes).frame(height: 80).padding(.vertical, 8) }
                    }
                }
            }
        }
        .navigationTitle(workspace?.label ?? "Space")
        .refreshable { await model.refresh() }
        .toolbar {
            Menu {
                Button("Rename space") { label = workspace?.label ?? ""; rename = true }
                Button("Add tab") { Task { await model.action("tab.create", params: ["workspace_id": workspaceID]) } }
                Button("Close space", role: .destructive) { close = true }
            } label: { Image(systemName: "ellipsis.circle") }.disabled(model.demo || model.client == nil)
        }
        .alert("Rename space", isPresented: $rename) {
            TextField("Name", text: $label)
            Button("Save") { Task { await model.action("workspace.rename", params: ["workspace_id": workspaceID, "label": label]) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Close this space and all its processes?", isPresented: $close, titleVisibility: .visible) {
            Button("Close space", role: .destructive) { Task { await model.action("workspace.close", params: ["workspace_id": workspaceID]) } }
        }
    }
}
