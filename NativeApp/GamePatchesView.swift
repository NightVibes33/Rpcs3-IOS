import SwiftUI

struct GamePatchesView: View {
    @EnvironmentObject private var controller: CoreController
    let game: RPCS3GameRecord

    private var patches: [RPCS3RuntimePatchRecord] {
        controller.runtimePatchesByTitleID[game.titleID] ?? []
    }

    private var grouped: [(name: String, entries: [RPCS3RuntimePatchRecord])] {
        let dictionary = Dictionary(grouping: patches) { patch in
            patch.patchGroup.isEmpty ? "Game Patches" : patch.patchGroup
        }
        return dictionary.keys.sorted().map { key in
            (name: key, entries: dictionary[key] ?? [])
        }
    }

    var body: some View {
        patchContent
            .navigationTitle("Game Patches")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                controller.refreshRuntimePatches(for: game)
            }
            .refreshable {
                controller.refreshRuntimePatches(for: game)
            }
    }

    @ViewBuilder
    private var patchContent: some View {
        if patches.isEmpty {
            ContentUnavailableView(
                "No Compatible Game Patches",
                systemImage: "wrench.and.screwdriver",
                description: Text(
                    "RPCS3 did not find Patch Engine entries for this title and app version in the currently installed patch repository."
                )
            )
        } else {
            List {
                Section {
                    Text(
                        "Game patches are RPCS3 Patch Engine modifications. Changes apply the next time the game boots; mutually exclusive entries in the same group are handled by RPCS3Core."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                ForEach(grouped, id: \.name) { group in
                    PatchGroupSection(game: game, name: group.name, entries: group.entries)
                }
            }
        }
    }
}

private struct PatchGroupSection: View {
    let game: RPCS3GameRecord
    let name: String
    let entries: [RPCS3RuntimePatchRecord]

    var body: some View {
        Section(name) {
            ForEach(entries, id: \.patchHash) { patch in
                RuntimePatchRow(game: game, patch: patch)
            }
        }
    }
}

private struct RuntimePatchRow: View {
    @EnvironmentObject private var controller: CoreController
    let game: RPCS3GameRecord
    let patch: RPCS3RuntimePatchRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: patchEnabledBinding) {
                patchLabel
            }
            .disabled(controller.state != .ready)

            if !patch.author.isEmpty {
                Text("By \(patch.author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !patch.notes.isEmpty {
                Text(patch.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if patch.configurableCount > 0 {
                Label(configurableText, systemImage: "slider.horizontal.3")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var patchEnabledBinding: Binding<Bool> {
        Binding(
            get: { patch.enabled },
            set: { enabled in
                controller.setRuntimePatch(for: game, patch: patch, enabled: enabled)
            }
        )
    }

    private var patchLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(patch.patchDescription.isEmpty ? patch.title : patch.patchDescription)
                .font(.headline)

            HStack(spacing: 8) {
                if !patch.patchVersion.isEmpty {
                    Text("Patch \(patch.patchVersion)")
                }
                if !patch.appVersion.isEmpty {
                    Text("App \(patch.appVersion)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var configurableText: String {
        let suffix = patch.configurableCount == 1 ? "" : "s"
        return "\(patch.configurableCount) configurable option\(suffix)"
    }
}
