import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var controller: CoreController

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RPCS3MetalSurface(controller: controller)
                .ignoresSafeArea()
                .opacity(controller.sessionRunning ? 1 : 0.001)
                .allowsHitTesting(controller.sessionRunning)

            if controller.sessionRunning {
                PS3TouchControllerOverlay(controller: controller)
                sessionOverlay
            } else {
                AppShellView()
            }
        }
        .fileImporter(
            isPresented: $controller.showingImporter,
            allowedContentTypes: [.data, .archive, .diskImage],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                controller.install(url: url)
            }
        }
    }

    private var sessionOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Menu {
                    Button(controller.touchControllerVisible ? "Hide Touch Controller" : "Show Touch Controller") {
                        controller.touchControllerVisible.toggle()
                        if !controller.touchControllerVisible {
                            controller.clearVirtualPad()
                        }
                    }
                    Button("Stop Emulation", role: .destructive) {
                        controller.stopSession()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.hierarchical)
                        .padding(16)
                }
            }
            Spacer()
        }
        .foregroundStyle(.white)
    }
}

struct AppShellView: View {
    @EnvironmentObject private var controller: CoreController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CoreLaunchView()

                    if controller.coreReady {
                        GamesView()

                        VStack(spacing: 12) {
                            Button {
                                controller.launchBigPicture()
                            } label: {
                                Label("Big Picture Mode", systemImage: "gamecontroller.fill")
                                    .frame(maxWidth: .infinity)
                                    .font(.headline)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(controller.state != .ready)

                            Button {
                                controller.showingImporter = true
                            } label: {
                                Label("Install Firmware / Content", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(controller.state != .ready)
                        }
                    }

                    StatusCard()
                }
                .frame(maxWidth: 620)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(.black)
            .navigationTitle("RPCS3")
        }
        .preferredColorScheme(.dark)
    }
}

struct CoreLaunchView: View {
    @EnvironmentObject private var controller: CoreController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "playstation.logo")
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text("RPCS3")
                        .font(.largeTitle.bold())
                    Text("PlayStation 3 emulator")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !controller.coreReady {
                Picker("JIT arena", selection: $controller.jitCapacityMiB) {
                    Text("Adaptive").tag(UInt32(0))
                    Text("512 MiB").tag(UInt32(512))
                    Text("768 MiB").tag(UInt32(768))
                    Text("1 GiB").tag(UInt32(1024))
                }
                .pickerStyle(.segmented)
                .disabled(controller.state == .starting)

                Button {
                    controller.start()
                } label: {
                    HStack {
                        if controller.state == .starting {
                            ProgressView().tint(.white)
                        }
                        Text(controller.state == .starting ? "Starting RPCS3…" : "Start")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!controller.canStart)
            } else {
                Label("RPCS3Core ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }

            Text("On iOS 26 and later, launch RPCS3 from StikDebug with its built-in Universal JIT script before pressing Start.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct StatusCard: View {
    @EnvironmentObject private var controller: CoreController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status")
                .font(.headline)
            Text(controller.status)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)

            if !controller.buildInfo.isEmpty {
                DisclosureGroup("RPCS3Core build") {
                    Text(controller.buildInfo)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}


struct GamesView: View {
    @EnvironmentObject private var controller: CoreController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Games")
                    .font(.title2.bold())
                Spacer()
                Button {
                    controller.refreshGames()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(controller.state != .ready)
            }

            if controller.games.isEmpty {
                ContentUnavailableView(
                    "No Games Installed",
                    systemImage: "gamecontroller",
                    description: Text("Install a PKG, ISO, or ZIP with RPCS3Core, then refresh the library.")
                )
                .frame(minHeight: 180)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(controller.games, id: \.titleID) { game in
                        GameRow(game: game)
                    }
                }
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct GameRow: View {
    @EnvironmentObject private var controller: CoreController
    let game: RPCS3GameRecord

    var body: some View {
        Button {
            controller.launch(game: game)
        } label: {
            HStack(spacing: 14) {
                gameIcon
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    Text(game.title.isEmpty ? game.titleID : game.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(game.titleID)
                        if !game.version.isEmpty {
                            Text("v\(game.version)")
                        }
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                    if game.sizeOnDisk > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: game.sizeOnDisk), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                Image(systemName: "play.fill")
                    .foregroundStyle(game.bootable ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!game.bootable || controller.state != .ready)
    }

    @ViewBuilder
    private var gameIcon: some View {
        if !game.iconPath.isEmpty, let image = UIImage(contentsOfFile: game.iconPath) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                Image(systemName: "gamecontroller.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
