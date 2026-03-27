import SwiftUI

struct PresetManagementView: View {
    @Environment(AppState.self) private var appState
    @State private var presetStore = PresetStore()
    @State private var selectedPresetID: UUID?
    @State private var isRenaming = false
    @State private var renameName = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Saved Presets")
                    .font(.title2.bold())
                Spacer()

                if appState.eqProfile != nil {
                    Button("Save Current as Preset") {
                        saveCurrentAsPreset()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if presetStore.presets.isEmpty {
                ContentUnavailableView {
                    Label("No Presets Saved", systemImage: "archivebox")
                } description: {
                    Text("Generate an EQ profile and save it as a preset to access it later.")
                }
            } else {
                List(selection: $selectedPresetID) {
                    ForEach(presetStore.presets) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name)
                                    .font(.headline)

                                HStack(spacing: 12) {
                                    if let device = preset.deviceResponseName {
                                        Label(device, systemImage: "headphones")
                                    }
                                    Text(preset.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    Text("\(preset.eqProfile.bands.count) bands")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                if !preset.notes.isEmpty {
                                    Text(preset.notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }

                            Spacer()

                            Button("Load") {
                                loadPreset(preset)
                            }
                            .buttonStyle(.bordered)
                        }
                        .tag(preset.id)
                        .contextMenu {
                            Button("Load") { loadPreset(preset) }
                            Button("Rename…") { startRename(preset) }
                            Divider()
                            Button("Delete", role: .destructive) {
                                presetStore.deletePreset(id: preset.id)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            presetStore.deletePreset(id: presetStore.presets[index].id)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $isRenaming) {
            VStack(spacing: 16) {
                Text("Rename Preset")
                    .font(.headline)
                TextField("Preset name", text: $renameName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                HStack {
                    Button("Cancel") { isRenaming = false }
                    Button("Rename") {
                        if let id = selectedPresetID,
                           var preset = presetStore.presets.first(where: { $0.id == id }) {
                            preset.name = renameName
                            presetStore.updatePreset(preset)
                        }
                        isRenaming = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    private func saveCurrentAsPreset() {
        guard let profile = appState.eqProfile else { return }
        let preset = EQPreset(
            name: "EQ Preset \(presetStore.presets.count + 1)",
            audiogram: appState.audiogram,
            deviceResponseName: appState.deviceResponse?.name,
            eqProfile: profile
        )
        presetStore.addPreset(preset)
    }

    private func loadPreset(_ preset: EQPreset) {
        appState.audiogram = preset.audiogram
        appState.eqProfile = preset.eqProfile
        appState.selectedNavItem = .results
    }

    private func startRename(_ preset: EQPreset) {
        selectedPresetID = preset.id
        renameName = preset.name
        isRenaming = true
    }
}
