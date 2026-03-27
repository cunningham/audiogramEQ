import Foundation

/// Export format options for EQ settings
enum ExportFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case parametricText = "Parametric EQ Text"
    case autoEQ = "AutoEQ Format"
    case json = "JSON"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .parametricText: "txt"
        case .autoEQ: "txt"
        case .json: "json"
        }
    }
}

/// A saved EQ preset with full context
struct EQPreset: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var audiogram: Audiogram
    var deviceResponseName: String?
    var eqProfile: EQProfile
    var createdAt: Date
    var updatedAt: Date
    var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        audiogram: Audiogram,
        deviceResponseName: String? = nil,
        eqProfile: EQProfile,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.audiogram = audiogram
        self.deviceResponseName = deviceResponseName
        self.eqProfile = eqProfile
        self.createdAt = Date()
        self.updatedAt = Date()
        self.notes = notes
    }
}
