import SwiftUI

struct RPCNView: View {
    @EnvironmentObject private var controller: CoreController
    @State private var username = ""
    @State private var password = ""
    @State private var token = ""
    @State private var ipv6 = false
    @State private var didLoadDraft = false

    var body: some View {
        List {
            Section("Status") {
                if let config = controller.rpcnConfig {
                    LabeledContent("Server", value: config.host.isEmpty ? "Not selected" : config.host)
                    LabeledContent("Username", value: config.username.isEmpty ? "Not configured" : config.username)
                    LabeledContent("Connection", value: config.authenticated
                        ? "Authenticated"
                        : (config.connected ? "Connected" : "Disconnected"))
                    if !config.onlineName.isEmpty {
                        LabeledContent("Online name", value: config.onlineName)
                    }
                }

                Text(controller.rpcnStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Account") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textContentType(.password)

                TextField("Verification token (optional)", text: $token)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: token) { _, newValue in
                        let normalized = String(newValue.uppercased().filter {
                            $0.isNumber || ($0 >= "A" && $0 <= "Z")
                        }.prefix(16))
                        if normalized != newValue {
                            token = normalized
                        }
                    }

                Toggle("IPv6 support", isOn: $ipv6)

                Button {
                    controller.saveRPCNCredentials(
                        username: username,
                        password: password,
                        token: token,
                        ipv6: ipv6
                    )
                } label: {
                    Label("Save RPCN Credentials", systemImage: "key.fill")
                }
                .disabled(
                    controller.state != .ready ||
                    username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    password.isEmpty ||
                    (!token.isEmpty && token.count != 16)
                )

                Button {
                    controller.testRPCNAccount()
                } label: {
                    Label("Test RPCN Account", systemImage: "checkmark.shield.fill")
                }
                .disabled(controller.state != .ready || controller.rpcnConfig?.hasPassword != true)

                Text("The original password is stored in iOS Keychain. RPCS3Core transforms it for RPCN and removes plaintext credentials from rpcn.yml.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Servers") {
                ForEach(controller.rpcnServers, id: \.host) { server in
                    RPCNServerRow(server: server)
                }

                NavigationLink {
                    RPCNAddServerView()
                } label: {
                    Label("Add RPCN Server", systemImage: "plus.circle")
                }
                .disabled(controller.state != .ready)
            }
        }
        .navigationTitle("RPCN")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            controller.refreshRPCN()
            loadDraftIfNeeded()
        }
        .refreshable {
            controller.refreshRPCN()
        }
        .onChange(of: controller.rpcnConfig?.username) { _, _ in
            loadDraftIfNeeded(force: false)
        }
    }

    private func loadDraftIfNeeded(force: Bool = false) {
        if didLoadDraft && !force { return }

        if let stored = RPCNCredentialVault.load() {
            username = stored.username
            password = stored.password
            token = stored.token
            ipv6 = stored.ipv6
            didLoadDraft = true
            return
        }

        if let config = controller.rpcnConfig {
            username = config.username
            ipv6 = config.ipv6Support
            didLoadDraft = true
        }
    }
}

private struct RPCNServerRow: View {
    @EnvironmentObject private var controller: CoreController
    let server: RPCS3RPCNServerRecord

    var body: some View {
        HStack {
            Button {
                controller.selectRPCNServer(server)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(server.serverDescription.isEmpty ? server.host : server.serverDescription)
                            .foregroundStyle(.primary)
                        Text(server.host)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if server.selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(controller.state != .ready || server.selected)

            if server.removable {
                Button(role: .destructive) {
                    controller.removeRPCNServer(server)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(controller.state != .ready)
            }
        }
    }
}

private struct RPCNAddServerView: View {
    @EnvironmentObject private var controller: CoreController
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var host = ""

    var body: some View {
        Form {
            Section("Custom RPCN Server") {
                TextField("Description", text: $description)
                TextField("Host", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button("Add Server") {
                    controller.addRPCNServer(description: description, host: host)
                    dismiss()
                }
                .disabled(
                    description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    controller.state != .ready
                )
            }
        }
        .navigationTitle("Add RPCN Server")
        .navigationBarTitleDisplayMode(.inline)
    }
}
