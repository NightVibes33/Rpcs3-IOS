import SwiftUI

struct SettingsView: View {
    var body: some View {
        EmuSettingsView()
    }
}

struct EmuSettingsView: View {
    @EnvironmentObject private var controller: CoreController
    @State private var showingResetConfirmation = false

    private var grouped: [(String, [RPCS3SettingRecord])] {
        let dictionary = Dictionary(grouping: controller.globalSettings) { setting in
            setting.category.isEmpty ? "General" : setting.category
        }
        return dictionary.keys.sorted().map { ($0, dictionary[$0] ?? []) }
    }

    var body: some View {
        Group {
            if controller.globalSettings.isEmpty {
                ContentUnavailableView(
                    "No RPCS3 Settings",
                    systemImage: "slider.horizontal.3",
                    description: Text("Start RPCS3Core to load the audited settings catalog.")
                )
            } else {
                List {
                    Section("Configuration Database") {
                        Button {
                            controller.syncConfigDatabase()
                        } label: {
                            Label("Sync RPCS3 Config Database", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(controller.state != .ready)

                        Text(controller.configDatabaseStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(grouped, id: \.0) { category, settings in
                        SettingsCategoryView(
                            title: category,
                            settings: settings,
                            onCommit: { setting, value in
                                controller.setGlobalSetting(setting, value: value)
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle("RPCS3 Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            controller.refreshGlobalSettings()
        }
        .refreshable {
            controller.refreshGlobalSettings()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Restore RPCS3 Defaults", role: .destructive) {
                        showingResetConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(controller.state != .ready)
            }
        }
        .confirmationDialog(
            "Restore all exposed RPCS3 settings to defaults?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults", role: .destructive) {
                controller.resetGlobalSettings()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct GameSettingsView: View {
    @EnvironmentObject private var controller: CoreController
    let game: RPCS3GameRecord
    @State private var showingResetConfirmation = false
    @State private var showingRemoveConfirmation = false

    private var settings: [RPCS3SettingRecord] {
        controller.gameSettingsByTitleID[game.titleID] ?? []
    }

    private var grouped: [(String, [RPCS3SettingRecord])] {
        let dictionary = Dictionary(grouping: settings) { setting in
            setting.category.isEmpty ? "General" : setting.category
        }
        return dictionary.keys.sorted().map { ($0, dictionary[$0] ?? []) }
    }

    var body: some View {
        Group {
            if settings.isEmpty {
                ContentUnavailableView(
                    "No Game Settings",
                    systemImage: "slider.horizontal.3",
                    description: Text("RPCS3 did not return a per-game settings catalog for this title.")
                )
            } else {
                List {
                    if controller.gameHasCustomConfig[game.titleID] == true {
                        Section {
                            Label("Custom configuration active", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }

                    ForEach(grouped, id: \.0) { category, records in
                        SettingsCategoryView(
                            title: category,
                            settings: records,
                            onCommit: { setting, value in
                                controller.setGameSetting(for: game, setting: setting, value: value)
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle("Game Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            controller.refreshGameSettings(for: game)
        }
        .refreshable {
            controller.refreshGameSettings(for: game)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Restore RPCS3 Defaults") {
                        showingResetConfirmation = true
                    }
                    if controller.gameHasCustomConfig[game.titleID] == true {
                        Button("Use Global Settings", role: .destructive) {
                            showingRemoveConfirmation = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(controller.state != .ready)
            }
        }
        .confirmationDialog(
            "Restore RPCS3 defaults for this game?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults", role: .destructive) {
                controller.resetGameSettings(for: game)
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Remove this game's custom configuration?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Use Global Settings", role: .destructive) {
                controller.removeGameSettings(for: game)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The title will inherit RPCS3's global settings.")
        }
    }
}

struct SettingsCategoryView: View {
    let title: String
    let settings: [RPCS3SettingRecord]
    let onCommit: (RPCS3SettingRecord, String) -> Void

    var body: some View {
        Section(title) {
            ForEach(settings.sorted(by: settingsSort), id: \.key) { setting in
                RPCS3SettingRow(setting: setting) { value in
                    onCommit(setting, value)
                }
            }
        }
    }

    private func settingsSort(_ lhs: RPCS3SettingRecord, _ rhs: RPCS3SettingRecord) -> Bool {
        if lhs.section != rhs.section { return lhs.section < rhs.section }
        return lhs.name < rhs.name
    }
}

private struct RPCS3SettingRow: View {
    let setting: RPCS3SettingRecord
    let onCommit: (String) -> Void
    @State private var draft: String

    init(setting: RPCS3SettingRecord, onCommit: @escaping (String) -> Void) {
        self.setting = setting
        self.onCommit = onCommit
        _draft = State(initialValue: setting.value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            settingControl

            if !setting.settingDescription.isEmpty {
                Text(setting.settingDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if !setting.defaultValue.isEmpty {
                    Text("Default: \(setting.defaultValue)")
                }
                if !setting.recommendedValue.isEmpty {
                    Text("Recommended: \(setting.recommendedValue)")
                        .foregroundStyle(.blue)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .onChange(of: setting.value) { _, newValue in
            draft = newValue
        }
    }

    @ViewBuilder
    private var settingControl: some View {
        switch setting.kind {
        case 0:
            Toggle(setting.name, isOn: Binding(
                get: {
                    let value = draft.lowercased()
                    return value == "true" || value == "1" || value == "enabled"
                },
                set: { enabled in
                    let value = enabled ? "true" : "false"
                    draft = value
                    onCommit(value)
                }
            ))

        case 3:
            HStack {
                Text(setting.name)
                Spacer()
                SettingsPicker(
                    setting: setting,
                    selection: Binding(
                        get: { draft },
                        set: { value in
                            draft = value
                            onCommit(value)
                        }
                    )
                )
            }

        case 1, 2, 4:
            VStack(alignment: .leading, spacing: 6) {
                Text(setting.name)
                HStack {
                    TextField(setting.defaultValue, text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(setting.kind == 1 ? .numbersAndPunctuation :
                            (setting.kind == 2 ? .decimalPad : .default))
                    Button("Apply") {
                        onCommit(draft)
                    }
                    .buttonStyle(.bordered)
                    .disabled(draft == setting.value)
                }
                if setting.kind == 1 || setting.kind == 2 {
                    Text(rangeDescription)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

        default:
            LabeledContent(setting.name, value: setting.value)
        }
    }

    private var rangeDescription: String {
        let step = setting.step
        if step > 0 {
            return "Range \(format(setting.minimum))–\(format(setting.maximum)), step \(format(step))"
        }
        return "Range \(format(setting.minimum))–\(format(setting.maximum))"
    }

    private func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.3g", value)
    }
}

struct SettingsPicker: View {
    let setting: RPCS3SettingRecord
    @Binding var selection: String

    var body: some View {
        Picker(setting.name, selection: $selection) {
            if setting.options.isEmpty {
                Text(selection).tag(selection)
            } else {
                ForEach(setting.options, id: \.value) { option in
                    Text(option.label.isEmpty ? option.value : option.label)
                        .tag(option.value)
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }
}
