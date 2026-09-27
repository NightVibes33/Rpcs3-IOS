import SwiftUI

struct RPCNView: View {
    @EnvironmentObject private var controller: CoreController
    @State private var username = ""
    @State private var password = ""
    @State private var token = ""
    @State private var ipv6 = false
    @State private var didLoadDraft = false
    @State private var friendUsername = ""

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


            Section("Friends & Social") {
                HStack {
                    TextField("RPCN username", text: $friendUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        controller.performRPCNSocialAction(0, username: friendUsername)
                        friendUsername = ""
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .disabled(
                        controller.state != .ready ||
                        friendUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                ForEach(controller.rpcnSocial, id: \.username) { entry in
                    RPCNSocialRow(entry: entry)
                }

                if controller.rpcnSocial.isEmpty {
                    Text("No RPCN friends, requests, blocked users, or recent players returned.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                NavigationLink {
                    RPCNAccountManagementView()
                } label: {
                    Label("Manage RPCN Account", systemImage: "person.crop.circle.badge.gearshape")
                }
                .disabled(controller.state != .ready)
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
            controller.refreshRPCNSocial()
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


private struct RPCNSocialRow: View {
    @EnvironmentObject private var controller: CoreController
    let entry: RPCS3RPCNSocialRecord

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(entry.isOnline ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.username)
                    .font(.headline)
                if !entry.presenceTitle.isEmpty {
                    Text(entry.presenceTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !entry.historyDescriptionText.isEmpty {
                    Text(entry.historyDescriptionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Menu {
                socialActions
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .disabled(controller.state != .ready)
        }
    }

    @ViewBuilder
    private var socialActions: some View {
        switch entry.kind {
        case 0:
            Button("Remove Friend", role: .destructive) {
                controller.performRPCNSocialAction(1, username: entry.username)
            }
            Button("Block User", role: .destructive) {
                controller.performRPCNSocialAction(5, username: entry.username)
            }
        case 1:
            Button("Accept Request") {
                controller.performRPCNSocialAction(2, username: entry.username)
            }
            Button("Reject Request", role: .destructive) {
                controller.performRPCNSocialAction(3, username: entry.username)
            }
            Button("Block User", role: .destructive) {
                controller.performRPCNSocialAction(5, username: entry.username)
            }
        case 2:
            Button("Cancel Request", role: .destructive) {
                controller.performRPCNSocialAction(4, username: entry.username)
            }
        case 3:
            Button("Unblock User") {
                controller.performRPCNSocialAction(6, username: entry.username)
            }
        case 4:
            Button("Add Friend") {
                controller.performRPCNSocialAction(0, username: entry.username)
            }
            Button("Block User", role: .destructive) {
                controller.performRPCNSocialAction(5, username: entry.username)
            }
        default:
            EmptyView()
        }
    }
}


private struct RPCNAccountManagementView: View {
    @EnvironmentObject private var controller: CoreController
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var resetToken = ""
    @State private var newPassword = ""
    @State private var ipv6 = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Create Account") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                Toggle("IPv6 support", isOn: $ipv6)

                Button("Create RPCN Account") {
                    controller.createRPCNAccount(
                        username: username,
                        password: password,
                        email: email,
                        ipv6: ipv6
                    )
                }
                .disabled(
                    controller.state != .ready ||
                    username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    password.isEmpty
                )
            }

            Section("Verification") {
                Button("Resend Verification Token") {
                    controller.resendRPCNVerificationToken()
                }
                .disabled(controller.state != .ready || controller.rpcnConfig?.hasPassword != true)
            }

            Section("Password Reset") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()

                Button("Request Reset Token") {
                    controller.requestRPCNPasswordReset(username: username, email: email)
                }
                .disabled(
                    controller.state != .ready ||
                    username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                TextField("16-character reset token", text: $resetToken)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: resetToken) { _, newValue in
                        let normalized = String(newValue.uppercased().filter {
                            $0.isNumber || ($0 >= "A" && $0 <= "Z")
                        }.prefix(16))
                        if normalized != newValue {
                            resetToken = normalized
                        }
                    }

                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)

                Button("Reset Password") {
                    controller.resetRPCNPassword(
                        username: username,
                        token: resetToken,
                        newPassword: newPassword
                    )
                }
                .disabled(
                    controller.state != .ready ||
                    username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    resetToken.count != 16 ||
                    newPassword.isEmpty
                )
            }

            Section {
                Button("Delete RPCN Account", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .disabled(controller.state != .ready || controller.rpcnConfig?.hasPassword != true)

                Text(controller.rpcnStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("RPCN Account")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let stored = RPCNCredentialVault.load() {
                username = stored.username
                password = stored.password
                ipv6 = stored.ipv6
            } else if let config = controller.rpcnConfig {
                username = config.username
                ipv6 = config.ipv6Support
            }
        }
        .confirmationDialog(
            "Permanently delete this RPCN account?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete RPCN Account", role: .destructive) {
                controller.deleteRPCNAccount()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
