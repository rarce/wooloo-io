import Foundation
import UserNotifications
import WoolooCore

@MainActor final class AgentNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AgentNotifications()
    var onOpen: ((String) -> Void)?
    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    func enable() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
    func reconcile(previous: Snapshot?, next: Snapshot) async {
        guard let previous else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        for pane in next.panes {
            let before = previous.panes.first { $0.id == pane.id }
            guard let before, before.agentStatus != pane.agentStatus,
                  pane.agentStatus == .blocked || pane.agentStatus == .done else { continue }
            let content = UNMutableNotificationContent()
            content.title = pane.agentStatus == .blocked ? "An agent needs you" : "An agent finished"
            content.body = pane.displayTitle
            content.sound = .default
            content.userInfo = ["pane_id": pane.id]
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pane-\(pane.id)", content: content, trigger: nil))
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let pane = response.notification.request.content.userInfo["pane_id"] as? String { await MainActor.run { self.onOpen?(pane) } }
    }
}
