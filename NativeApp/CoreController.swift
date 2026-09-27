import Foundation
import SwiftUI
import AVFAudio
import GameController

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

    private let core = RPCS3DynamicCore.shared()
    private let worker = DispatchQueue(label: "com.nightvibes33.rpcs3.core", qos: .userInitiated)
    private var metalView: RPCS3MetalView?
    private var inputManager: GameControllerInputManager?

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
                    self.inputManager = GameControllerInputManager(core: core)
                    self.inputManager?.start()
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

    func launch(game: RPCS3GameRecord) {
        guard state == .ready, game.bootable else { return }
        guard attachCurrentSurface() else {
            fail(core.lastError.isEmpty ? "RPCS3Core is not ready for a video surface." : core.lastError)
            return
        }

        state = .launching
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
                    self.status = game.title
                } else {
                    self.state = .ready
                    self.status = message.isEmpty ? "RPCS3 could not boot \(game.title)." : message
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
        status = "Starting RPCS3 Big Picture Mode"
        let core = self.core
        worker.async { [weak self] in
            let ok = core.bootBigPicture()
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                if ok {
                    self.state = .running
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

    func stopSession() {
        guard state == .running || state == .launching else { return }
        let core = self.core
        worker.async { [weak self] in
            let ok = core.stop()
            let message = core.lastError
            DispatchQueue.main.async {
                guard let self else { return }
                self.state = ok ? .ready : .failed
                self.status = ok
                    ? "RPCS3 session stopped. RPCS3Core remains initialized."
                    : message
            }
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

final class GameControllerInputManager {
    private weak var core: RPCS3DynamicCore?
    private var timer: Timer?

    init(core: RPCS3DynamicCore) {
        self.core = core
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
        guard let gamepad = GCController.controllers().first?.extendedGamepad else {
            _ = core.setPlayerOne(
                connected: false,
                buttons: 0,
                leftX: 0, leftY: 0,
                rightX: 0, rightY: 0,
                leftTrigger: 0, rightTrigger: 0
            )
            return
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

        _ = core.setPlayerOne(
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
