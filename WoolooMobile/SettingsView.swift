import SwiftUI
import WoolooCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var publicKey = ""
    @State private var keyText = ""
    @State private var passphrase = ""
    @State private var error: String?
    @State private var importKey = false
    @State private var notices = "License text unavailable. See THIRD_PARTY_NOTICES.md in the source repository."
    var body: some View {
        NavigationStack {
            Form {
                Section("Your device SSH key") {
                    Text("Authorize this public key in Wooloo on your Mac → Remote Access, or add it to the server's authorized_keys.").font(.subheadline)
                    Text(publicKey).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    ShareLink(item: publicKey) { Label("Share public key", systemImage: "square.and.arrow.up") }.disabled(publicKey.isEmpty)
                    Button("Copy public key") { UIPasteboard.general.string = publicKey }.disabled(publicKey.isEmpty)
                    DisclosureGroup("Import an Ed25519 OpenSSH key") {
                        Text("This replaces the device key. Keep a working server login for recovery.").font(.caption).foregroundStyle(.secondary)
                        SecureField("OpenSSH private key", text: $keyText)
                        SecureField("Passphrase (if encrypted)", text: $passphrase)
                        Button("Review replacement", role: .destructive) { importKey = true }.disabled(keyText.isEmpty)
                    }
                }
                Section("Agent alerts") {
                    Button("Enable local notifications") { Task { do { let allowed = try await AgentNotifications.shared.enable(); if !allowed { error = "Notifications are disabled. You can enable them in iOS Settings." } } catch { self.error = error.localizedDescription } } }
                    Text("Alerts arrive while this app is connected in the foreground. Background push alerts need a separate server service and are not included.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Text("No analytics, Wooloo account, or intermediary server. SSH connects directly to the machines you choose. Private keys and saved passwords stay in this device's Keychain and are not synced to iCloud.")
                    Text("Connections close in the background and reconnect when you return. Agents keep running on your computer.")
                }
                Section("About") {
                    LabeledContent("Wooloo Mobile", value: "iOS Preview 0.1.0")
                    Link("wooloo.dev", destination: URL(string: "https://wooloo.dev")!)
                    Link("Source & support", destination: URL(string: "https://github.com/rarce/wooloo-io")!)
                    NavigationLink("Third-party notices") {
                        ScrollView { Text(notices).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() }.navigationTitle("Notices")
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
            .task {
                if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) { notices = text }
                do { publicKey = try SecretStore.publicKey() } catch { self.error = error.localizedDescription } }
            .confirmationDialog("Replace this device's SSH key?", isPresented: $importKey, titleVisibility: .visible) {
                Button("Replace key", role: .destructive) {
                    do { try SecretStore.importKey(keyText, passphrase: passphrase); publicKey = try SecretStore.publicKey(); keyText = ""; passphrase = "" }
                    catch { self.error = "Key import failed. Use an Ed25519 OpenSSH key with its correct passphrase." }
                }
            }
            .onDisappear { keyText = ""; passphrase = "" }
        }
    }
}
