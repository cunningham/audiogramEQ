import Foundation

/// Manages saving and loading EQ presets from disk
@Observable
final class PresetStore {
    var presets: [EQPreset] = []

    private var presetsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AudiogramEQ", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("presets.json")
    }

    init() {
        loadPresets()
    }

    func loadPresets() {
        guard let data = try? Data(contentsOf: presetsURL) else { return }
        presets = (try? JSONDecoder().decode([EQPreset].self, from: data)) ?? []
    }

    func savePresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        try? data.write(to: presetsURL, options: .atomic)
    }

    func addPreset(_ preset: EQPreset) {
        presets.append(preset)
        savePresets()
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        savePresets()
    }

    func updatePreset(_ preset: EQPreset) {
        if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[idx] = preset
            savePresets()
        }
    }
}
