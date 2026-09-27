import SwiftUI

struct GameInfoDetailsView: View {
    @EnvironmentObject private var controller: CoreController
    let game: RPCS3GameRecord

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    gameArtwork
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(game.title.isEmpty ? game.titleID : game.title)
                            .font(.title3.bold())
                        Text(game.titleID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        if !game.version.isEmpty {
                            Text("Version \(game.version)")
                                .foregroundStyle(.secondary)
                        }
                        if !game.firmwareVersion.isEmpty {
                            Text("Requires firmware \(game.firmwareVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    controller.launch(game: game)
                } label: {
                    Label("Start Game", systemImage: "play.fill")
                }
                .disabled(!game.bootable || controller.state != .ready)
            }

            Section("Manage") {
                NavigationLink {
                    GameTrophiesView(game: game)
                } label: {
                    Label("Trophies", systemImage: "trophy.fill")
                }

                NavigationLink {
                    SavestateManagerView(game: game)
                } label: {
                    Label("Save State Manager", systemImage: "clock.arrow.circlepath")
                }

                NavigationLink {
                    GameSettingsView(game: game)
                } label: {
                    Label("Game Settings", systemImage: "slider.horizontal.3")
                }

                NavigationLink {
                    GamePatchesView(game: game)
                } label: {
                    Label("Manage Game Patches", systemImage: "wrench.and.screwdriver")
                }
            }

            Section("Installation") {
                LabeledContent("Category", value: game.category.isEmpty ? "Unknown" : game.category)
                LabeledContent("Size", value: ByteCountFormatter.string(
                    fromByteCount: Int64(clamping: game.sizeOnDisk),
                    countStyle: .file
                ))
                if !game.path.isEmpty {
                    LabeledContent("RPCS3 path") {
                        Text(game.path)
                            .font(.caption.monospaced())
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle(game.title.isEmpty ? game.titleID : game.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var gameArtwork: some View {
        if !game.iconPath.isEmpty, let image = UIImage(contentsOfFile: game.iconPath) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.quaternary)
                Image(systemName: "gamecontroller.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct GameTrophiesView: View {
    @EnvironmentObject private var controller: CoreController
    let game: RPCS3GameRecord

    private var trophies: [RPCS3TrophyRecord] {
        (controller.trophiesByTitleID[game.titleID] ?? [])
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    var body: some View {
        Group {
            if trophies.isEmpty {
                ContentUnavailableView(
                    "No Registered Trophies",
                    systemImage: "trophy",
                    description: Text("Start this game once so RPCS3 can register its PS3 trophy set.")
                )
            } else {
                List(trophies, id: \.trophyID) { trophy in
                    TrophyRow(trophy: trophy)
                }
            }
        }
        .navigationTitle("Trophies")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            controller.refreshTrophies(for: game)
        }
        .refreshable {
            controller.refreshTrophies(for: game)
        }
    }
}

private struct TrophyRow: View {
    let trophy: RPCS3TrophyRecord

    var body: some View {
        HStack(spacing: 14) {
            trophyArtwork
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                Text(displayDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    Text(gradeName)
                    if trophy.earned {
                        Label("Earned", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption2.weight(.semibold))
            }
            Spacer()
        }
        .opacity(trophy.earned ? 1 : 0.72)
    }

    private var displayName: String {
        if trophy.hidden && !trophy.earned { return "Hidden Trophy" }
        return trophy.name.isEmpty ? "Trophy #\(trophy.trophyID)" : trophy.name
    }

    private var displayDescription: String {
        if trophy.hidden && !trophy.earned { return "This trophy is hidden until earned." }
        return trophy.trophyDescription
    }

    private var gradeName: String {
        switch trophy.grade {
        case 1: return "Platinum"
        case 2: return "Gold"
        case 3: return "Silver"
        case 4: return "Bronze"
        default: return "Unknown"
        }
    }

    @ViewBuilder
    private var trophyArtwork: some View {
        if !trophy.iconPath.isEmpty, let image = UIImage(contentsOfFile: trophy.iconPath) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SavestateManagerView: View {
    @EnvironmentObject private var controller: CoreController
    let game: RPCS3GameRecord

    private var savestates: [RPCS3SavestateRecord] {
        (controller.savestatesByTitleID[game.titleID] ?? [])
            .sorted { $0.modifiedTime > $1.modifiedTime }
    }

    var body: some View {
        Group {
            if savestates.isEmpty {
                ContentUnavailableView(
                    "No Save States",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("RPCS3 has no retained save states for this title.")
                )
            } else {
                List(savestates, id: \.identifier) { savestate in
                    SavestateRow(game: game, savestate: savestate)
                }
            }
        }
        .navigationTitle("Save State Manager")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            controller.refreshSavestates(for: game)
        }
        .refreshable {
            controller.refreshSavestates(for: game)
        }
    }
}

private struct SavestateRow: View {
    @EnvironmentObject private var controller: CoreController
    let game: RPCS3GameRecord
    let savestate: RPCS3SavestateRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: savestate.compatible ? "clock.badge.checkmark" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(savestate.compatible ? .green : .orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(modifiedDate)
                    .font(.headline)
                Text(ByteCountFormatter.string(
                    fromByteCount: Int64(clamping: savestate.size),
                    countStyle: .file
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(savestate.compatible
                    ? "Compatible with this RPCS3 build"
                    : "Incompatible with this RPCS3 build")
                    .font(.caption2)
                    .foregroundStyle(savestate.compatible ? .secondary : .orange)
            }

            Spacer()

            Button {
                controller.launch(game: game, savestate: savestate)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!savestate.compatible || controller.state != .ready)
        }
    }

    private var modifiedDate: String {
        guard savestate.modifiedTime > 0 else { return savestate.identifier }
        let date = Date(timeIntervalSince1970: TimeInterval(savestate.modifiedTime))
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
