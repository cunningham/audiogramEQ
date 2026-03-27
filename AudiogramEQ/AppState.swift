import SwiftUI

enum NavigationItem: String, Hashable, CaseIterable, Identifiable {
    case manualInput = "Manual Input"
    case importAudiogram = "Import Audiogram"
    case deviceResponse = "Device Response"
    case results = "EQ Results"
    case presets = "Presets"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .manualInput: "slider.horizontal.3"
        case .importAudiogram: "doc.viewfinder"
        case .deviceResponse: "headphones"
        case .results: "waveform.path.ecg"
        case .presets: "archivebox"
        }
    }

    var section: NavigationSection {
        switch self {
        case .manualInput, .importAudiogram: .input
        case .deviceResponse: .process
        case .results: .output
        case .presets: .output
        }
    }
}

enum NavigationSection: String, CaseIterable {
    case input = "Input"
    case process = "Process"
    case output = "Output"
}

@Observable
final class AppState {
    var selectedNavItem: NavigationItem? = .manualInput
    var audiogram = Audiogram()
    var deviceResponse: FrequencyResponseCurve?
    var eqProfile: EQProfile?
    var presets: [EQPreset] = []

    var hasAudiogramData: Bool {
        !audiogram.leftEar.isEmpty || !audiogram.rightEar.isEmpty
    }

    var hasDeviceResponse: Bool {
        deviceResponse != nil
    }

    // Settings
    var numberOfEQBands: Int = 10
    var maxGainDB: Double = 20.0
    var preferredExportFormat: ExportFormat = .parametricText

    func reset() {
        audiogram = Audiogram()
        deviceResponse = nil
        eqProfile = nil
    }
}
