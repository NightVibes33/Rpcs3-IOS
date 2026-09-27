import Foundation
import SwiftUI
import AVFAudio
import GameController

struct VirtualPadSnapshot {
    var buttons: UInt64 = 0
    var leftX: Float = 0
    var leftY: Float = 0
    var rightX: Float = 0
    var rightY: Float = 0
    var leftTrigger: Float = 0
    var rightTrigger: Float = 0
}

@MainActor
final class CoreController: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case ready
        case launching
        case running
        case failed
    }

    @Published var state: State = .stopped
    @Published var status = "Run RPCS3 through StikDebug, then press Start."
    @Published var jitCapacityMiB: UInt32 = 1024
    @Published var showingImporter = false
    @Published var games: [RPCS3GameRecord] = []
    @Published var hasPhysicalController = !GCController.controllers().isEmpty
    @Published var touchControllerVisible = true
    @Published var bootStage = ""
    @Published var bootFraction: Double?
    @Published var performanceSummary = ""
    @Published var trophiesByTitleID: [String: [RPCS3TrophyRecord]] = [:]
    @Published var savestatesByTitleID: [String: [RPCS3SavestateRecord]] = [:]
    @Published var savestateExportURL: URL?
    @Published var globalSettings: [RPCS3SettingRecord] = []
    @Published var gameSettingsByTitleID: [String: [RPCS3SettingRecord]] = [:]
    @Published var gameHasCustomConfig: [String: Bool] = [:]
    @Published var gameSettingsPresetsByTitleID: [String: [RPCS3GameSettingsPresetRecord]] = [:]
    @Published var runtimePatchesByTitleID: [String: [RPCS3RuntimePatchRecord]] = [:]
    @Published var configDatabaseStatus = "Not synced this session"
    @Published var rpcnConfig: RPCS3RPCNConfigRecord?
    @Published var rpcnServers: [RPCS3RPCNServerRecord] = []
    @Published var rpcnStatus = "RPCN not loaded"
    @Published var rpcnSocial: [RPCS3RPCNSocialRecord] = []
    @Published var gameUpdatesByTitleID: [String: [PS3GameUpdatePackage]] = [:]
    @Published var gameUpdateStatusByTitleID: [String: String] = [:]
    @Published var gameCacheByTitleID: [String: RPCS3GameCacheRecord] = [:]

    private var virtualPad = VirtualPadSnapshot()
    private let core = RPCS3DynamicCore.shared()
    private let worker = DispatchQueue(label: "com.nightvibes33.rpcs3.core", qos: .userInitiated)
    private var metalView: RPCS3MetalView?
    private var inputManager: GameControllerInputManager?
    private var telemetryTimer: Timer?
    private var cacheRoot: URL?

    var coreReady: Bool { state == .ready || state == .launching || state == .running }
    var sessionRunning: Bool { state == .running }
    var canStart: Bool { state == .stopped || state == .failed }
    var buildInfo: String { core.buildInfo }

    var diagnosticsLogURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RPCS3 Logs", isDirectory: true)
            .appendingPathComponent("ios-host.log", isDirectory: false)
    }

    var diagnosticsLogAvailable: Bool {
        guard let diagnosticsLogURL else { return false }
        return FileManager.default.fileExists(atPath: diagnosticsLogURL.path)
    }

    func registerMetalView(_ view: RPCS3MetalView) {
        metalView = view
        if coreReady {
            _ = attachCurrentSurface()
        }
    }

    func start() {
        guard canStart else { return }

        let fm = FileManager.default
        guard let supportBase = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let cacheBase = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            fail("Unable to resolve the RPCS3 sandbox directories.")
            return
        }

        let support = supportBase.appendingPathComponent("RPCS3", isDirectory: true)
        let cache = cacheBase.appendingPathComponent("RPCS3", isDirectory: true)
        cacheRoot = cache

        do {
            try fm.createDirectory(at: support, withIntermediateDirectories: true)
            try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        } catch {
            fail("Unable to prepare RPCS3 storage: \(error.localizedDescription)")
            return
        }

        configureAudioSession()
        state = .starting
        status = "Start: loading libRPCS3Core.dylib"

        let capacity = jitCapacityMiB
        let supportPath = support.path
        let cachePath = cache.path
        let core = self.core

        worker.async { [weak self] in
            let ok = core.start(
                supportPath: supportPath,
                cachePath: cachePath,
                jitCapacityMiB: capacity
            )
            let message = core.lastError

            DispatchQueue.main.async {
                guard let self else { return }
                if ok {
                    self.state = .ready
                    self.status = "RPCS3Core startup completed"
                    self.inputManager = GameControllerInputManager(
                        core: core,
                        virtualState: { [weak self] in self?.virtualPad ?? VirtualPadSnapshot() },
                        physicalStateChanged: { [weak self] connected in
                            self?.hasPhysicalController = connected
                        }
                    )
                    self.inputManager?.start()
                    self.startTelemetry()
                    _ = self.attachCurrentSurface()
                    self.refreshGames()
                    self.restoreRPCNCredentialsFromKeychain()
                } else {
                    self.fail(message.isEmpty
                        ? "Unable to load RPCS3Core. Run the app from StikDebug with its Universal JIT script."
                        : message)
                }
            }
        }
    }

    func refreshGames() {
        guard coreReady else { return }
        let core = self.core
        worker.async { [weak self] in
            let records = core.enumerateGames()
            DispatchQueue.main.async {
                self?.games = records
            }
        }
    }

    func refreshGameCache(for game: RPCS3GameRecord) {
        guard coreReady, state == .ready else { return }
        let core = self.core
        let titleID = game.titleID
        worker.async { [weak self] in
            let info = core.gameCacheInfo(titleID: titleID)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.gameCacheByTitleID[titleID] = info
                if info.totalBytes == 0 && !message.isEmpty {
                    self.status = message
                }
            }
        }
    }

    func clearGameCache(for game: RPCS3GameRecord, type: UInt32) {
        guard coreReady, state == .ready else { return }
        let core = self.core
        let titleID = game.titleID
        worker.async { [weak self] in
            var removed: UInt64 = 0
            let ok = core.clearGameCache(titleID: titleID, type: type, bytesRemoved: &removed)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = ok
                    ? "Cleared \(ByteCountFormatter.string(fromByteCount: Int64(clamping: removed), countStyle: .file)) of RPCS3 cache."
                    : message
                if ok { self.refreshGameCache(for: game) }
            }
        }
    }

    func deleteInstalledGame(_ game: RPCS3GameRecord) {
        guard coreReady, state == .ready else { return }
        let core = self.core
        let titleID = game.titleID
        worker.async { [weak self] in
            let ok = core.deleteGame(titleID: titleID)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = ok ? "Deleted \(game.title)." : message
                if ok {
                    self.gameCacheByTitleID.removeValue(forKey: titleID)
                    self.refreshGames()
                }
            }
        }
    }

    func checkGameUpdates(for game: RPCS3GameRecord) {
        guard coreReady, state == .ready else { return }
        let titleID = game.titleID
        let installedVersion = game.version
        gameUpdateStatusByTitleID[titleID] = "Checking Sony for updates…"

        let core = self.core
        worker.async { [weak self] in
            guard let data = core.gameUpdateManifest(titleID: titleID) else {
                let message = core.lastError
                DispatchQueue.main.async {
                    self?.gameUpdateStatusByTitleID[titleID] =
                        message.isEmpty ? "Unable to fetch the game-update manifest." : message
                }
                return
            }

            do {
                let all = try PS3GameUpdateManifest.parse(data)
                let newer = all.filter {
                    PS3GameUpdateManifest.isNewer($0.version, than: installedVersion)
                }
                DispatchQueue.main.async {
                    self?.gameUpdatesByTitleID[titleID] = newer
                    self?.gameUpdateStatusByTitleID[titleID] = newer.isEmpty
                        ? "No newer PlayStation 3 update packages found."
                        : "\(newer.count) newer update package\(newer.count == 1 ? "" : "s") available."
                }
            } catch {
                DispatchQueue.main.async {
                    self?.gameUpdateStatusByTitleID[titleID] =
                        "Could not parse Sony's update manifest: \(error.localizedDescription)"
                }
            }
        }
    }

    func installAllGameUpdates(for game: RPCS3GameRecord) {
        guard coreReady, state == .ready,
              let cacheRoot else { return }

        let titleID = game.titleID
        let packages = (gameUpdatesByTitleID[titleID] ?? [])
            .sorted { PS3GameUpdateManifest.compareVersions($0.version, $1.version) == .orderedAscending }
        guard !packages.isEmpty else {
            gameUpdateStatusByTitleID[titleID] = "No pending updates."
            return
        }

        gameUpdateStatusByTitleID[titleID] = "Starting ordered update batch…"
        let core = self.core
        let updateDirectory = cacheRoot.appendingPathComponent("game-updates", isDirectory: true)

        worker.async { [weak self] in
            do {
                try FileManager.default.createDirectory(
                    at: updateDirectory,
                    withIntermediateDirectories: true
                )

                for (index, package) in packages.enumerated() {
                    let safeVersion = package.version.replacingOccurrences(
                        of: "[^0-9A-Za-z._-]",
                        with: "_",
                        options: .regularExpression
                    )
                    let destination = updateDirectory
                        .appendingPathComponent("\(titleID)-\(safeVersion).pkg")

                    DispatchQueue.main.async {
                        self?.gameUpdateStatusByTitleID[titleID] =
                            "Downloading \(package.version) (\(index + 1)/\(packages.count))…"
                    }

                    try? FileManager.default.removeItem(at: destination)
                    guard core.downloadGameUpdate(
                        packageURL: package.url,
                        destinationPath: destination.path,
                        expectedSize: package.size
                    ) else {
                        throw NSError(
                            domain: "RPCS3.GameUpdater",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey:
                                core.lastError.isEmpty ? "RPCS3Core could not download update \(package.version)." : core.lastError]
                        )
                    }

                    guard package.sha1.count == 40 else {
                        try? FileManager.default.removeItem(at: destination)
                        throw NSError(
                            domain: "RPCS3.GameUpdater",
                            code: 3,
                            userInfo: [NSLocalizedDescriptionKey:
                                "Sony's manifest did not provide a valid SHA-1 for update \(package.version)."]
                        )
                    }

                    DispatchQueue.main.async {
                        self?.gameUpdateStatusByTitleID[titleID] =
                            "Verifying \(package.version)…"
                    }
                    let actualSHA1 = try PS3PackageIntegrity.sha1Hex(of: destination)
                    guard actualSHA1.caseInsensitiveCompare(package.sha1) == .orderedSame else {
                        try? FileManager.default.removeItem(at: destination)
                        throw NSError(
                            domain: "RPCS3.GameUpdater",
                            code: 4,
                            userInfo: [NSLocalizedDescriptionKey:
                                "SHA-1 verification failed for update \(package.version)."]
                        )
                    }

                    DispatchQueue.main.async {
                        self?.gameUpdateStatusByTitleID[titleID] =
                            "Installing \(package.version) (\(index + 1)/\(packages.count))…"
                    }
                    guard core.installGamePatch(
                        titleID: titleID,
                        packagePath: destination.path
                    ) else {
                        try? FileManager.default.removeItem(at: destination)
                        throw NSError(
                            domain: "RPCS3.GameUpdater",
                            code: 5,
                            userInfo: [NSLocalizedDescriptionKey:
                                core.lastError.isEmpty ? "RPCS3Core rejected update \(package.version)." : core.lastError]
                        )
                    }

                    try? FileManager.default.removeItem(at: destination)
                }

                DispatchQueue.main.async {
                    guard let self else { return }
                    self.gameUpdateStatusByTitleID[titleID] = "All selected PlayStation 3 updates installed."
                    self.gameUpdatesByTitleID[titleID] = []
                    self.refreshGames()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.gameUpdateStatusByTitleID[titleID] = error.localizedDescription
                }
            }
        }
    }

    func createRPCNAccount(username: String, password: String, email: String, ipv6: Bool) {
        guard coreReady, state == .ready else { return }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty, !address.isEmpty else {
            rpcnStatus = "RPCN username, password, and email are required."
            return
        }

        rpcnStatus = "Creating RPCN account…"
        let core = self.core
        worker.async { [weak self] in
            let ok = core.createRPCNAccount(username: user, password: password, email: address)
            let message = core.lastError
            if ok {
                try? RPCNCredentialVault.save(RPCNStoredCredentials(
                    username: user,
                    password: password,
                    token: "",
                    ipv6: ipv6
                ))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.rpcnStatus = ok
                    ? "RPCN account created. Check your email for the verification token."
                    : message
                if ok { self.refreshRPCN() }
            }
        }
    }

    func resendRPCNVerificationToken() {
        guard coreReady, state == .ready else { return }
        rpcnStatus = "Requesting a new RPCN verification token…"
        let core = self.core
        worker.async { [weak self] in
            let ok = core.resendRPCNToken()
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.rpcnStatus = ok
                    ? "RPCN verification token requested. Check your email."
                    : message
            }
        }
    }

    func requestRPCNPasswordReset(username: String, email: String) {
        guard coreReady, state == .ready else { return }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !address.isEmpty else {
            rpcnStatus = "RPCN username and email are required."
            return
        }

        rpcnStatus = "Requesting RPCN password-reset token…"
        let core = self.core
        worker.async { [weak self] in
            let ok = core.requestRPCNPasswordReset(username: user, email: address)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.rpcnStatus = ok
                    ? "RPCN password-reset token requested. Check your email."
                    : message
            }
        }
    }

    func resetRPCNPassword(username: String, token: String, newPassword: String) {
        guard coreReady, state == .ready else { return }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !user.isEmpty, normalizedToken.count == 16, !newPassword.isEmpty else {
            rpcnStatus = "RPCN reset requires a username, 16-character token, and new password."
            return
        }

        rpcnStatus = "Resetting RPCN password…"
        let core = self.core
        worker.async { [weak self] in
            let ok = core.resetRPCNPassword(
                username: user,
                resetToken: normalizedToken,
                newPassword: newPassword
            )
            let message = core.lastError

            if ok, let stored = RPCNCredentialVault.load(), stored.username == user {
                try? RPCNCredentialVault.save(RPCNStoredCredentials(
                    username: stored.username,
                    password: newPassword,
                    token: stored.token,
                    ipv6: stored.ipv6
                ))
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.rpcnStatus = ok ? "RPCN password reset completed." : message
                if ok { self.refreshRPCN() }
            }
        }
    }

    func deleteRPCNAccount() {
        guard coreReady, state == .ready else { return }
        rpcnStatus = "Deleting RPCN account…"
        let core = self.core
        worker.async { [weak self] in
            let ok = core.deleteRPCNAccount()
            let message = core.lastError
            if ok {
                try? RPCNCredentialVault.delete()
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.rpcnStatus = ok ? "RPCN account deleted." : message
                if ok {
                    self.rpcnSocial = []
                    self.refreshRPCN()
                }
            }
        }
    }

    func refreshRPCNSocial() {
        guard coreReady, state == .ready else { return }
        let core = self.core
        worker.async { [weak self] in
            let records = core.rpcnSocial()
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.rpcnSocial = records
                if records.isEmpty && !message.isEmpty {
                    self.rpcnStatus = message
                }
            }
        }
    }

    func performRPCNSocialAction(_ action: UInt32, username: String) {
        guard coreReady, state == .ready else { return }
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let core = self.core
        worker.async { [weak self] in
            let ok = core.performRPCNSocialAction(action, username: normalized)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.rpcnStatus = ok ? "RPCN social action completed for \(normalized)." : message
                if ok { self.refreshRPCNSocial() }
            }
        }
    }

    func refreshRPCN() {
        guard coreReady else { return }
        let core = self.core
        worker.async { [weak self] in
            let config = core.rpcnConfig()
            let servers = core.rpcnServers()
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.rpcnConfig = config
                self.rpcnServers = servers
                if config.authenticated {
                    self.refreshRPCNSocial()
                }
                if config.authenticated {
                    self.rpcnStatus = "Authenticated as \(config.onlineName.isEmpty ? config.username : config.onlineName)"
                } else if config.connected {
                    self.rpcnStatus = "Connected to \(config.host)"
                } else if !config.username.isEmpty {
                    self.rpcnStatus = "Configured as \(config.username)"
                } else {
                    self.rpcnStatus = message.isEmpty ? "RPCN not configured" : message
                }
            }
        }
    }

    func restoreRPCNCredentialsFromKeychain() {
        guard coreReady, state == .ready else { return }
        guard let stored = RPCNCredentialVault.load(),
              !stored.username.isEmpty,
              !stored.password.isEmpty else {
            refreshRPCN()
            return
        }

        rpcnStatus = "Restoring RPCN credentials from Keychain…"
        let core = self.core
        worker.async { [weak self] in
            let ok = core.setRPCNCredentials(
                username: stored.username,
                password: stored.password,
                token: stored.token,
                ipv6: stored.ipv6
            )
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.rpcnStatus = ok
                    ? "RPCN credentials restored from Keychain."
                    : (message.isEmpty ? "RPCN credential restore failed." : message)
                self.refreshRPCN()
            }
        }
    }

    func saveRPCNCredentials(username: String, password: String, token: String, ipv6: Bool) {
        guard coreReady, state == .ready else { return }

        let normalizedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedUser.isEmpty, !password.isEmpty else {
            rpcnStatus = "RPCN username and password are required."
            return
        }

        rpcnStatus = "Saving RPCN credentials…"
        let core = self.core
        worker.async { [weak self] in
            let ok = core.setRPCNCredentials(
                username: normalizedUser,
                password: password,
                token: normalizedToken,
                ipv6: ipv6
            )
            let message = core.lastError

            if ok {
                do {
                    try RPCNCredentialVault.save(RPCNStoredCredentials(
                        username: normalizedUser,
                        password: password,
                        token: normalizedToken,
                        ipv6: ipv6
                    ))
                } catch {
                    DispatchQueue.main.async {
                        self?.rpcnStatus = "RPCN saved in the core, but Keychain save failed: \(error.localizedDescription)"
                        self?.refreshRPCN()
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.rpcnStatus = ok
                    ? "RPCN credentials saved."
                    : (message.isEmpty ? "RPCN credential update failed." : message)
                self.refreshRPCN()
            }
        }
    }

    func selectRPCNServer(_ server: RPCS3RPCNServerRecord) {
        guard coreReady, state == .ready else { return }
        let core = self.core
        let host = server.host
        worker.async { [weak self] in
            let ok = core.setRPCNServer(host: host)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.rpcnStatus = ok ? "Selected RPCN server \(host)." : message
                self.refreshRPCN()
            }
        }
    }

    func addRPCNServer(description: String, host: String) {
        guard coreReady, state == .ready else { return }
        let name = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !serverHost.isEmpty else {
            rpcnStatus = "RPCN server name and host are required."
            return
        }

        let core = self.core
        worker.async { [weak self] in
            let ok = core.addRPCNServer(description: name, host: serverHost)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.rpcnStatus = ok ? "Added RPCN server \(serverHost)." : message
                self.refreshRPCN()
            }
        }
    }

    func removeRPCNServer(_ server: RPCS3RPCNServerRecord) {
        guard coreReady, state == .ready, server.removable else { return }
        let core = self.core
        let description = server.serverDescription
        let host = server.host
        worker.async { [weak self] in
            let ok = core.removeRPCNServer(description: description, host: host)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.rpcnStatus = ok ? "Removed RPCN server \(host)." : message
                self.refreshRPCN()
            }
        }
    }

    func testRPCNAccount() {
        guard coreReady, state == .ready else { return }
        rpcnStatus = "Testing RPCN account…"
        let core = self.core
        worker.async { [weak self] in
            let ok = core.testRPCNAccount()
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.rpcnStatus = ok ? "RPCN authentication succeeded." : message
                self.refreshRPCN()
            }
        }
    }

    func syncConfigDatabase() {
        guard coreReady, state == .ready else { return }
        configDatabaseStatus = "Downloading RPCS3 configuration database…"

        guard let url = URL(string: "https://api.rpcs3.net/config/?api=v1") else {
            configDatabaseStatus = "RPCS3 configuration endpoint is invalid."
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      !data.isEmpty else {
                    self.configDatabaseStatus = "RPCS3 configuration database returned an invalid response."
                    return
                }

                let core = self.core
                self.worker.async { [weak self] in
                    let ok = core.updateConfigDatabase(data: data)
                    let message = core.lastError
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.configDatabaseStatus = ok
                            ? "RPCS3 configuration database synced."
                            : (message.isEmpty ? "RPCS3 rejected the configuration database." : message)
                        if ok {
                            self.refreshGlobalSettings()
                            for game in self.games {
                                self.refreshGameSettings(for: game)
                            }
                        }
                    }
                }
            } catch {
                self.configDatabaseStatus = "Config database download failed: \(error.localizedDescription)"
            }
        }
    }

    func refreshRuntimePatches(for game: RPCS3GameRecord) {
        guard coreReady, state == .ready else { return }
        let core = self.core
        let titleID = game.titleID
        let appVersion = game.version
        worker.async { [weak self] in
            let records = core.runtimePatches(titleID: titleID, appVersion: appVersion)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.runtimePatchesByTitleID[titleID] = records
                if records.isEmpty && !message.isEmpty {
                    self.status = message
                }
            }
        }
    }

    func setRuntimePatch(for game: RPCS3GameRecord, patch: RPCS3RuntimePatchRecord, enabled: Bool) {
        guard coreReady, state == .ready else { return }
        let core = self.core
        let titleID = game.titleID
        let hashValue = patch.patchHash
        let title = patch.title
        let appVersion = patch.appVersion
        let description = patch.patchDescription
        worker.async { [weak self] in
            let ok = core.setRuntimePatch(
                titleID: titleID,
                hash: hashValue,
                title: title,
                appVersion: appVersion,
                description: description,
                enabled: enabled
            )
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = ok
                    ? "\(enabled ? "Enabled" : "Disabled") \(description)."
                    : message
                if ok { self.refreshRuntimePatches(for: game) }
            }
        }
    }

    func refreshGlobalSettings() {
        guard coreReady, state == .ready else { return }
        let core = self.core
        worker.async { [weak self] in
            let snapshot = core.globalSettings()
            let records = snapshot.settings
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.globalSettings = records
                if records.isEmpty && !message.isEmpty {
                    self.status = message
                }
            }
        }
    }

    func setGlobalSetting(_ setting: RPCS3SettingRecord, value: String) {
        guard coreReady, state == .ready else { return }
        let core = self.core
        let key = setting.key
        worker.async { [weak self] in
            let ok = core.setGlobalSetting(key: key, value: value)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = ok ? "Saved \(setting.name)." : message
                if ok { self.refreshGlobalSettings() }
            }
        }
    }

    func resetGlobalSettings() {
        guard coreReady, state == .ready else { return }
        let core = self.core
        worker.async { [weak self] in
            let ok = core.resetGlobalSettings()
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = ok ? "Restored RPCS3 global settings to defaults." : message
                if ok { self.refreshGlobalSettings() }
            }
        }
    }

    func refreshGameSettingsPresets(for game: RPCS3GameRecord) {
        guard coreReady, state == .ready else { return }
        let core = self.core
        let titleID = game.titleID
        worker.async { [weak self] in
            let records = core.gameSettingsPresets(titleID: titleID)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.gameSettingsPresetsByTitleID[titleID] = records
                if records.isEmpty && !message.isEmpty { self.status = message }
            }
        }
    }

    func saveGameSettingsPreset(for game: RPCS3GameRecord, name: String) {
        mutateGameSettingsPreset(game, success: "Saved preset \(name).") {
            $0.saveGameSettingsPreset(titleID: game.titleID, name: name)
        }
    }

    func applyGameSettingsPreset(for game: RPCS3GameRecord, name: String) {
        mutateGameSettingsPreset(game, success: "Applied preset \(name).") {
            $0.applyGameSettingsPreset(titleID: game.titleID, name: name)
        }
    }

    func duplicateGameSettingsPreset(for game: RPCS3GameRecord, source: String, destination: String) {
        mutateGameSettingsPreset(game, success: "Duplicated preset as \(destination).") {
            $0.duplicateGameSettingsPreset(titleID: game.titleID, sourceName: source, destinationName: destination)
        }
    }

    func renameGameSettingsPreset(for game: RPCS3GameRecord, source: String, destination: String) {
        mutateGameSettingsPreset(game, success: "Renamed preset to \(destination).") {
            $0.renameGameSettingsPreset(titleID: game.titleID, sourceName: source, destinationName: destination)
        }
    }

    func deleteGameSettingsPreset(for game: RPCS3GameRecord, name: String) {
        mutateGameSettingsPreset(game, success: "Deleted preset \(name).") {
            $0.deleteGameSettingsPreset(titleID: game.titleID, name: name)
        }
    }

    private func mutateGameSettingsPreset(
        _ game: RPCS3GameRecord,
        success: String,
        operation: @escaping (RPCS3DynamicCore) -> Bool
    ) {
        guard coreReady, state == .ready else { return }
        let core = self.core
        worker.async { [weak self] in
            let ok = operation(core)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = ok ? success : message
                if ok {
                    self.refreshGameSettings(for: game)
                    self.refreshGameSettingsPresets(for: game)
                }
            }
        }
    }

    func refreshGameSettings(for game: RPCS3GameRecord) {
        guard coreReady, state == .ready else { return }
        let core = self.core
        let titleID = game.titleID
        worker.async { [weak self] in
            let snapshot = core.gameSettings(titleID: titleID)
            let records = snapshot.settings
            let hasCustom = snapshot.hasCustomConfig
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.gameSettingsByTitleID[titleID] = records
                self.gameHasCustomConfig[titleID] = hasCustom
                if records.isEmpty && !message.isEmpty {
                    self.status = message
                }
            }
        }
    }

    func setGameSetting(for game: RPCS3GameRecord, setting: RPCS3SettingRecord, value: String) {
        guard coreReady, state == .ready else { return }
        let core = self.core
        let titleID = game.titleID
        let key = setting.key
        worker.async { [weak self] in
            let ok = core.setGameSetting(titleID: titleID, key: key, value: value)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = ok ? "Saved \(setting.name) for \(game.title)." : message
                if ok { self.refreshGameSettings(for: game) }
            }
        }
    }

    func resetGameSettings(for game: RPCS3GameRecord) {
        guard coreReady, state == .ready else { return }
        let core = self.core
        let titleID = game.titleID
        worker.async { [weak self] in
            let ok = core.resetGameSettings(titleID: titleID)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = ok ? "Restored RPCS3 defaults for \(game.title)." : message
                if ok { self.refreshGameSettings(for: game) }
            }
        }
    }

    func removeGameSettings(for game: RPCS3GameRecord) {
        guard coreReady, state == .ready else { return }
        let core = self.core
        let titleID = game.titleID
        worker.async { [weak self] in
            let ok = core.removeGameSettings(titleID: titleID)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = ok ? "\(game.title) now inherits global RPCS3 settings." : message
                if ok { self.refreshGameSettings(for: game) }
            }
        }
    }

    func refreshTrophies(for game: RPCS3GameRecord) {
        guard coreReady else { return }
        let core = self.core
        let titleID = game.titleID
        worker.async { [weak self] in
            let records = core.enumerateTrophies(titleID: titleID)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.trophiesByTitleID[titleID] = records
                if records.isEmpty && !message.isEmpty {
                    self.status = message
                }
            }
        }
    }

    func refreshSavestates(for game: RPCS3GameRecord) {
        guard coreReady else { return }
        let core = self.core
        let titleID = game.titleID
        worker.async { [weak self] in
            let records = core.enumerateSavestates(titleID: titleID)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.savestatesByTitleID[titleID] = records
                if records.isEmpty && !message.isEmpty {
                    self.status = message
                }
            }
        }
    }

    func importSavestate(for game: RPCS3GameRecord, from url: URL) {
        guard coreReady, state == .ready, let cacheRoot else { return }
        let core = self.core
        let titleID = game.titleID
        status = "Importing save state…"

        worker.async { [weak self] in
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let staging = cacheRoot.appendingPathComponent("savestate-import", isDirectory: true)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                let safeName = url.lastPathComponent.replacingOccurrences(
                    of: "[^0-9A-Za-z._-]",
                    with: "_",
                    options: .regularExpression
                )
                let staged = staging.appendingPathComponent(safeName)
                try? FileManager.default.removeItem(at: staged)
                try FileManager.default.copyItem(at: url, to: staged)
                defer { try? FileManager.default.removeItem(at: staged) }

                let ok = core.importSavestate(titleID: titleID, sourcePath: staged.path)
                let message = core.lastError
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.status = ok ? "Save state imported." : message
                    if ok { self.refreshSavestates(for: game) }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.status = "Save-state import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func exportSavestate(for game: RPCS3GameRecord, savestate: RPCS3SavestateRecord) {
        guard coreReady, state == .ready, let cacheRoot else { return }
        let core = self.core
        let titleID = game.titleID
        let identifier = savestate.identifier
        status = "Exporting save state…"

        worker.async { [weak self] in
            do {
                let exportRoot = cacheRoot.appendingPathComponent("savestate-export", isDirectory: true)
                try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)

                let lower = identifier.lowercased()
                let suffix: String
                if lower.hasSuffix(".savestat.zst") {
                    suffix = ".SAVESTAT.zst"
                } else if lower.hasSuffix(".savestat.gz") {
                    suffix = ".SAVESTAT.gz"
                } else {
                    suffix = ".SAVESTAT"
                }

                let cleanTitle = titleID.replacingOccurrences(
                    of: "[^0-9A-Za-z._-]",
                    with: "_",
                    options: .regularExpression
                )
                let stamp = Int(Date().timeIntervalSince1970)
                let destination = exportRoot.appendingPathComponent("\(cleanTitle)-\(stamp)\(suffix)")
                try? FileManager.default.removeItem(at: destination)

                let ok = core.exportSavestate(
                    titleID: titleID,
                    savestateID: identifier,
                    destinationPath: destination.path
                )
                let message = core.lastError
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.savestateExportURL = ok ? destination : nil
                    self.status = ok ? "Save state exported and ready to share." : message
                }
            } catch {
                DispatchQueue.main.async {
                    self?.savestateExportURL = nil
                    self?.status = "Save-state export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func duplicateSavestate(for game: RPCS3GameRecord, savestate: RPCS3SavestateRecord) {
        guard coreReady, state == .ready else { return }
        let core = self.core
        let titleID = game.titleID
        let identifier = savestate.identifier
        worker.async { [weak self] in
            let ok = core.duplicateSavestate(titleID: titleID, identifier: identifier)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = ok ? "Save state duplicated." : message
                if ok { self.refreshSavestates(for: game) }
            }
        }
    }

    func deleteSavestate(for game: RPCS3GameRecord, savestate: RPCS3SavestateRecord) {
        guard coreReady, state == .ready else { return }
        let core = self.core
        let titleID = game.titleID
        let identifier = savestate.identifier
        worker.async { [weak self] in
            let ok = core.deleteSavestate(titleID: titleID, identifier: identifier)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = ok ? "Save state deleted." : message
                if ok { self.refreshSavestates(for: game) }
            }
        }
    }

    func launch(game: RPCS3GameRecord) {
        guard state == .ready, game.bootable else { return }
        guard attachCurrentSurface() else {
            fail(core.lastError.isEmpty ? "RPCS3Core is not ready for a video surface." : core.lastError)
            return
        }

        state = .launching
        bootStage = "Starting \(game.title)"
        bootFraction = nil
        status = "Starting \(game.title)…"
        let core = self.core
        let titleID = game.titleID
        worker.async { [weak self] in
            let ok = core.bootGame(titleID: titleID)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                if ok {
                    self.state = .running
                    self.bootStage = ""
                    self.bootFraction = nil
                    self.status = game.title
                } else {
                    self.state = .ready
                    self.status = message.isEmpty ? "RPCS3 could not boot \(game.title)." : message
                }
            }
        }
    }

    func launch(game: RPCS3GameRecord, savestate: RPCS3SavestateRecord) {
        guard state == .ready, game.bootable, savestate.compatible else { return }
        guard attachCurrentSurface() else {
            fail(core.lastError.isEmpty ? "RPCS3Core is not ready for a video surface." : core.lastError)
            return
        }

        state = .launching
        bootStage = "Loading save state for \(game.title)"
        bootFraction = nil
        status = "Loading save state…"
        let core = self.core
        let titleID = game.titleID
        let savestateID = savestate.identifier
        worker.async { [weak self] in
            let ok = core.bootGame(titleID: titleID, savestateID: savestateID)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                if ok {
                    self.state = .running
                    self.bootStage = ""
                    self.bootFraction = nil
                    self.status = game.title
                } else {
                    self.state = .ready
                    self.status = message.isEmpty ? "RPCS3 could not load the selected save state." : message
                }
            }
        }
    }

    func launchXMB() {
        guard state == .ready else { return }
        guard attachCurrentSurface() else {
            fail(core.lastError.isEmpty ? "RPCS3Core is not ready for a video surface." : core.lastError)
            return
        }

        state = .launching
        bootStage = "Starting PlayStation 3 XMB"
        bootFraction = nil
        status = "Starting PlayStation 3 XMB"
        let core = self.core
        worker.async { [weak self] in
            let ok = core.bootXMB()
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                if ok {
                    self.state = .running
                    self.bootStage = ""
                    self.bootFraction = nil
                    self.status = "PlayStation 3 XMB"
                } else {
                    self.state = .ready
                    self.status = message.isEmpty ? "PlayStation 3 XMB failed to start." : message
                }
            }
        }
    }

    func launchBigPicture() {
        guard state == .ready else { return }
        guard attachCurrentSurface() else {
            fail(core.lastError.isEmpty ? "RPCS3Core is not ready for a video surface." : core.lastError)
            return
        }

        state = .launching
        bootStage = "Starting RPCS3 Big Picture Mode"
        bootFraction = nil
        status = "Starting RPCS3 Big Picture Mode"
        let core = self.core
        worker.async { [weak self] in
            let ok = core.bootBigPicture()
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                if ok {
                    self.state = .running
                    self.bootStage = ""
                    self.bootFraction = nil
                    self.status = "Big Picture Mode"
                } else {
                    self.state = .ready
                    self.status = message.isEmpty ? "Big Picture Mode failed to start." : message
                }
            }
        }
    }

    func install(url: URL) {
        guard state == .ready else {
            status = "Start RPCS3Core before installing firmware or content."
            return
        }

        status = "Installing \(url.lastPathComponent)…"
        let core = self.core
        worker.async { [weak self] in
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }

            let ok = core.installContent(atPath: url.path)
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = ok
                    ? "\(url.lastPathComponent) installed by RPCS3Core."
                    : (message.isEmpty ? "RPCS3Core installation failed." : message)
                if ok { self.refreshGames() }
            }
        }
    }

    func setVirtualButton(_ mask: UInt64, pressed: Bool) {
        if pressed {
            virtualPad.buttons |= mask
        } else {
            virtualPad.buttons &= ~mask
        }
    }

    func setVirtualStick(left: Bool, x: Float, y: Float) {
        let clampedX = max(-1, min(1, x))
        let clampedY = max(-1, min(1, y))
        if left {
            virtualPad.leftX = clampedX
            virtualPad.leftY = clampedY
        } else {
            virtualPad.rightX = clampedX
            virtualPad.rightY = clampedY
        }
    }

    func setVirtualTrigger(left: Bool, value: Float) {
        let clamped = max(0, min(1, value))
        if left {
            virtualPad.leftTrigger = clamped
            setVirtualButton(UInt64(1 << 10), pressed: clamped > 0.05)
        } else {
            virtualPad.rightTrigger = clamped
            setVirtualButton(UInt64(1 << 11), pressed: clamped > 0.05)
        }
    }

    func clearVirtualPad() {
        virtualPad = VirtualPadSnapshot()
    }

    func stopSession() {
        guard state == .running || state == .launching else { return }
        let core = self.core
        worker.async { [weak self] in
            let ok = core.stop()
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.state = ok ? .ready : .failed
                self.bootStage = ""
                self.bootFraction = nil
                self.performanceSummary = ""
                self.clearVirtualPad()
                self.status = ok
                    ? "RPCS3 session stopped. RPCS3Core remains initialized."
                    : message
            }
        }
    }

    private func startTelemetry() {
        guard telemetryTimer == nil else { return }
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }

            if self.state == .launching {
                let progress = self.core.bootProgress()
                if progress.valid {
                    self.bootStage = progress.stage
                    self.bootFraction = progress.total > 0
                        ? Double(progress.completed) / Double(progress.total)
                        : nil
                }
            }

            if self.state == .running {
                let metrics = self.core.performanceMetrics()
                var parts: [String] = []
                if metrics.fpsValid {
                    parts.append(String(format: "%.1f FPS", metrics.framesPerSecond))
                }
                if metrics.cpuValid {
                    parts.append(String(format: "CPU %.0f%%", metrics.cpuUsagePercent))
                }
                if metrics.gpuValid {
                    parts.append(String(format: "RSX %.0f%%", metrics.gpuUsagePercent))
                }
                if metrics.memoryValid {
                    let used = ByteCountFormatter.string(
                        fromByteCount: Int64(clamping: metrics.memoryUsedBytes),
                        countStyle: .memory
                    )
                    parts.append("RAM \(used)")
                }
                self.performanceSummary = parts.joined(separator: "  •  ")
            } else if self.state != .launching {
                self.performanceSummary = ""
            }
        }
        if let telemetryTimer {
            RunLoop.main.add(telemetryTimer, forMode: .common)
        }
    }

    func sceneDidEnterBackground() {
        guard state == .running else { return }
        worker.async { [core] in _ = core.pause() }
    }

    func sceneDidBecomeActive() {
        guard state == .running else { return }
        worker.async { [core] in _ = core.resume() }
    }

    private func attachCurrentSurface() -> Bool {
        guard let view = metalView, coreReady else { return false }
        view.layoutIfNeeded()

        let drawable = view.metalLayer.drawableSize
        guard drawable.width >= 1, drawable.height >= 1 else { return false }

        let refresh = Float(view.window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond)
        return core.attach(
            metalLayer: view.metalLayer,
            width: UInt32(min(drawable.width.rounded(), Double(UInt32.max))),
            height: UInt32(min(drawable.height.rounded(), Double(UInt32.max))),
            refreshRate: max(20, refresh)
        )
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(512.0 / 48_000.0)
            try session.setActive(true)
        } catch {
            status = "Audio session warning: \(error.localizedDescription)"
        }
    }

    private func fail(_ message: String) {
        state = .failed
        status = message
    }
}

@MainActor
final class GameControllerInputManager {
    private weak var core: RPCS3DynamicCore?
    private let virtualState: () -> VirtualPadSnapshot
    private let physicalStateChanged: (Bool) -> Void
    private var timer: Timer?

    init(
        core: RPCS3DynamicCore,
        virtualState: @escaping () -> VirtualPadSnapshot,
        physicalStateChanged: @escaping (Bool) -> Void
    ) {
        self.core = core
        self.virtualState = virtualState
        self.physicalStateChanged = physicalStateChanged
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.push()
        }
        RunLoop.main.add(timer!, forMode: .common)
        push()
    }

    deinit {
        timer?.invalidate()
    }

    private func push() {
        guard let core else { return }

        let controllers = Array(GCController.controllers().prefix(7))
        if controllers.isEmpty {
            physicalStateChanged(false)
            let pad = virtualState()
            _ = core.setPlayer(
                index: 0,
                connected: true,
                buttons: pad.buttons,
                leftX: pad.leftX, leftY: pad.leftY,
                rightX: pad.rightX, rightY: pad.rightY,
                leftTrigger: pad.leftTrigger, rightTrigger: pad.rightTrigger
            )
            for player in 1..<7 {
                _ = core.setPlayer(
                    index: UInt32(player),
                    connected: false,
                    buttons: 0,
                    leftX: 0, leftY: 0,
                    rightX: 0, rightY: 0,
                    leftTrigger: 0, rightTrigger: 0
                )
            }
            return
        }

        physicalStateChanged(true)

        for player in 0..<7 {
            guard player < controllers.count,
                  let gamepad = controllers[player].extendedGamepad else {
                _ = core.setPlayer(
                    index: UInt32(player),
                    connected: false,
                    buttons: 0,
                    leftX: 0, leftY: 0,
                    rightX: 0, rightY: 0,
                    leftTrigger: 0, rightTrigger: 0
                )
                continue
            }

            var buttons: UInt64 = 0
            if gamepad.dpad.up.isPressed { buttons |= 1 << 0 }
            if gamepad.dpad.down.isPressed { buttons |= 1 << 1 }
            if gamepad.dpad.left.isPressed { buttons |= 1 << 2 }
            if gamepad.dpad.right.isPressed { buttons |= 1 << 3 }
            if gamepad.buttonA.isPressed { buttons |= 1 << 4 }
            if gamepad.buttonB.isPressed { buttons |= 1 << 5 }
            if gamepad.buttonX.isPressed { buttons |= 1 << 6 }
            if gamepad.buttonY.isPressed { buttons |= 1 << 7 }
            if gamepad.leftShoulder.isPressed { buttons |= 1 << 8 }
            if gamepad.rightShoulder.isPressed { buttons |= 1 << 9 }
            if gamepad.leftTrigger.isPressed { buttons |= 1 << 10 }
            if gamepad.rightTrigger.isPressed { buttons |= 1 << 11 }
            if gamepad.leftThumbstickButton?.isPressed == true { buttons |= 1 << 12 }
            if gamepad.rightThumbstickButton?.isPressed == true { buttons |= 1 << 13 }
            if gamepad.buttonMenu.isPressed { buttons |= 1 << 14 }
            if gamepad.buttonOptions?.isPressed == true { buttons |= 1 << 15 }
            if #available(iOS 14.0, *), gamepad.buttonHome?.isPressed == true { buttons |= 1 << 16 }

            _ = core.setPlayer(
                index: UInt32(player),
                connected: true,
                buttons: buttons,
                leftX: gamepad.leftThumbstick.xAxis.value,
                leftY: gamepad.leftThumbstick.yAxis.value,
                rightX: gamepad.rightThumbstick.xAxis.value,
                rightY: gamepad.rightThumbstick.yAxis.value,
                leftTrigger: gamepad.leftTrigger.value,
                rightTrigger: gamepad.rightTrigger.value
            )
        }
    }
}
