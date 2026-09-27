import SwiftUI

struct GameUpdatesView: View {
    @EnvironmentObject private var controller: CoreController
    let game: RPCS3GameRecord

    private var updates: [PS3GameUpdatePackage] {
        controller.gameUpdatesByTitleID[game.titleID] ?? []
    }

    private var status: String {
        controller.gameUpdateStatusByTitleID[game.titleID] ?? "Not checked"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Installed version", value: game.version.isEmpty ? "Unknown" : game.version)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    controller.checkGameUpdates(for: game)
                } label: {
                    Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(controller.state != .ready)

                if !updates.isEmpty {
                    Button {
                        controller.installAllGameUpdates(for: game)
                    } label: {
                        Label(
                            "Download & Install \(updates.count) Update\(updates.count == 1 ? "" : "s")",
                            systemImage: "square.and.arrow.down.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.state != .ready)
                }
            }

            if !updates.isEmpty {
                Section("Available Packages") {
                    ForEach(updates) { package in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Version \(package.version)")
                                    .font(.headline)
                                Spacer()
                                Text(ByteCountFormatter.string(
                                    fromByteCount: Int64(clamping: package.size),
                                    countStyle: .file
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            if !package.requiredSystemVersion.isEmpty {
                                Text("PS3 system software: \(package.requiredSystemVersion)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(package.url)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            Section {
                Text("Automatic downloads come directly from Sony through RPCS3Core. Packages are SHA-1 verified and installed in ascending version order because Sony manifests do not publish explicit dependency links.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Game Updates")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            controller.checkGameUpdates(for: game)
        }
        .refreshable {
            controller.checkGameUpdates(for: game)
        }
    }
}
