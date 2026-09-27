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

    private var virtualPad = VirtualPadSnapshot()
    private let core = RPCS3DynamicCore.shared()
    private let worker = DispatchQueue(label: "com.nightvibes33.rpcs3.core", qos: .userInitiated)
    private var metalView: RPCS3MetalView?
    private var inputManager: GameControllerInputManager?
    private var telemetryTimer: Timer?

    var coreReady: Bool { state == .ready || state == .launching || state == .running }
    var sessionRunning: Bool { state == .running }
    var canStart: Bool { state == .stopped || state == .failed }
    var buildInfo: String { core.buildInfo }

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
