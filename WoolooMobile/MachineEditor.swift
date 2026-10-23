import SwiftUI
import WoolooCore

struct MachineEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var machine: Machine
    @State private var password = ""
    @State private var accessID = ""
    @State private var accessSecret = ""
    @State private var link = ""
    @State private var error: String?
    @State private var fingerprints = ""
    @State private var review = false
    @State private var scan = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Import from Wooloo on your Mac") {
                    Button { scan = true } label: { Label("Scan QR or choose image", systemImage: "qrcode.viewfinder") }
                    TextField("Paste machine link", text: $link, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Import connection details") {
                        do {
                            let imported = try ConnectionLink.parse(link)
                            machine = imported; fingerprints = imported.fingerprints.joined(separator: "\n")
                            link = ""
                        } catch { self.error = error.localizedDescription }
                    }.disabled(link.isEmpty)
                }
                Section("Machine") {
                    Picker("Connection", selection: $machine.transport) { Text("Direct SSH").tag("ssh"); Text("Cloudflare Tunnel").tag("cloudflare") }
                    TextField("Name", text: $machine.name)
                    TextField("Hostname", text: $machine.host).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("SSH username", text: $machine.user).textInputAutocapitalization(.never).autocorrectionDisabled()
                    LabeledContent("Port") { TextField("22", value: $machine.port, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    TextField("Herdr session", text: $machine.session).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Herdr path (optional)", text: $machine.herdrPath).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    SecureField("Password (empty uses device SSH key)", text: $password)
                    Text("A new password replaces the saved password. Leaving this empty uses the device's Ed25519 key.").font(.caption).foregroundStyle(.secondary)
                } header: { Text("Authentication · stored in Keychain") }
                Section {
                    TextField("SHA256:… (one per line)", text: $fingerprints, axis: .vertical).font(.system(.caption, design: .monospaced)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Verify fingerprints in Wooloo Remote Access or with the server administrator. With no pins, connection stops and displays the server fingerprint for review; no credentials are sent until it is trusted.").font(.caption).foregroundStyle(.secondary)
                } header: { Text("Trusted server fingerprints") }
                if machine.transport == "cloudflare" {
                    Section("Cloudflare Access · optional") {
                        SecureField("Service token client ID", text: $accessID)
                        SecureField("Service token secret", text: $accessSecret)
                        Text("Uses wss://hostname/ with normal TLS verification. Leave both empty for a quick tunnel or a hostname without Access. Saving empty fields clears the previous token.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Machine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Review") {
                    do {
                        machine.fingerprints = fingerprints.split(whereSeparator: { $0.isNewline }).map(String.init)
                        try machine.validate()
                        for pin in machine.fingerprints {
                            guard pin.hasPrefix("SHA256:"), pin.count == 50 else { throw WoolooError.message("Use a full SHA256 SSH fingerprint.") }
                        }
                        review = true
                    } catch { self.error = error.localizedDescription }
                } }
            }
            .confirmationDialog("Save access to \(machine.user)@\(machine.host):\(machine.port)?", isPresented: $review, titleVisibility: .visible) {
                Button("Save reviewed machine") {
                    do {
                        if password.isEmpty { try SecretStore.delete("password-\(machine.id)") }
                        else { try SecretStore.write(Data(password.utf8), account: "password-\(machine.id)") }
                        if accessID.isEmpty && accessSecret.isEmpty {
                            try SecretStore.delete("access-id-\(machine.id)")
                            try SecretStore.delete("access-secret-\(machine.id)")
                        } else {
                            guard !accessID.isEmpty, !accessSecret.isEmpty else { throw WoolooError.message("Enter both Access token fields.") }
                            try SecretStore.write(Data(accessID.utf8), account: "access-id-\(machine.id)")
                            try SecretStore.write(Data(accessSecret.utf8), account: "access-secret-\(machine.id)")
                        }
                        model.save(machine)
                        if model.error == nil { password = ""; dismiss() }
                    } catch { self.error = error.localizedDescription }
                }
            } message: { Text("Session: \(machine.session). \(machine.fingerprints.isEmpty ? "Server identity must be verified on first connection." : "Only the reviewed server fingerprints will be accepted.")") }
            .sheet(isPresented: $scan) { QRImportView { link = $0 } }
            .onAppear { fingerprints = machine.fingerprints.joined(separator: "\n") }
            .onDisappear { password = ""; accessID = ""; accessSecret = "" }
        }
    }
}
