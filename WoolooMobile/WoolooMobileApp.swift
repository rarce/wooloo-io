import SwiftUI

@main struct WoolooMobileApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            MachinesView().environment(model).preferredColorScheme(.dark)
                .tint(.mint)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { model.foreground = false; model.disconnect() }
                    if phase == .active { model.foreground = true }
                    if phase == .active, let machine = model.selectedMachine, !model.demo, model.client == nil {
                        Task { await model.connect(machine) }
                    }
                }
                .task {
                    AgentNotifications.shared.onOpen = { model.notificationPaneID = $0 }
                    if ProcessInfo.processInfo.arguments.contains("--demo") { model.showDemo() }
                }
        }
    }
}
