import Foundation

/// Standard audiometric test frequencies in Hz
enum AudiometricFrequency: Double, CaseIterable, Codable, Sendable, Comparable {
    case hz250  = 250
    case hz500  = 500
    case hz1000 = 1000
    case hz2000 = 2000
    case hz3000 = 3000
    case hz4000 = 4000
    case hz6000 = 6000
    case hz8000 = 8000

    var displayLabel: String {
        let val = Int(rawValue)
        return val >= 1000 ? "\(val / 1000)k" : "\(val)"
    }

    static func < (lhs: AudiometricFrequency, rhs: AudiometricFrequency) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A single hearing threshold measurement
struct HearingThreshold: Codable, Sendable, Identifiable, Hashable {
    var id: AudiometricFrequency { frequency }
    let frequency: AudiometricFrequency
    /// Hearing level in dB HL (0 = normal, positive = hearing loss, -10 to 120 range)
    var thresholdDBHL: Double

    /// Clamps threshold to valid audiometric range
    var clampedThreshold: Double {
        min(max(thresholdDBHL, -10), 120)
    }
}

/// Complete audiogram data for both ears
struct Audiogram: Codable, Sendable, Hashable {
    var leftEar: [HearingThreshold]
    var rightEar: [HearingThreshold]
    var testDate: Date?
    var notes: String

    init(
        leftEar: [HearingThreshold] = [],
        rightEar: [HearingThreshold] = [],
        testDate: Date? = nil,
        notes: String = ""
    ) {
        self.leftEar = leftEar
        self.rightEar = rightEar
        self.testDate = testDate
        self.notes = notes
    }

    /// Creates an audiogram pre-populated with normal hearing (0 dB HL) at all frequencies
    static var normal: Audiogram {
        let thresholds = AudiometricFrequency.allCases.map {
            HearingThreshold(frequency: $0, thresholdDBHL: 0)
        }
        return Audiogram(leftEar: thresholds, rightEar: thresholds)
    }

    /// Creates an empty audiogram with all standard frequencies set to a default value
    static func blank(defaultDB: Double = 0) -> Audiogram {
        let thresholds = AudiometricFrequency.allCases.map {
            HearingThreshold(frequency: $0, thresholdDBHL: defaultDB)
        }
        return Audiogram(leftEar: thresholds, rightEar: thresholds)
    }

    /// Threshold at a specific frequency for the given ear, if available
    func threshold(at frequency: AudiometricFrequency, ear: Ear) -> Double? {
        let data = ear == .left ? leftEar : rightEar
        return data.first { $0.frequency == frequency }?.thresholdDBHL
    }

    /// Average hearing loss across speech frequencies (500, 1000, 2000, 4000 Hz)
    func puretoneAverage(ear: Ear) -> Double? {
        let speechFreqs: [AudiometricFrequency] = [.hz500, .hz1000, .hz2000, .hz4000]
        let data = ear == .left ? leftEar : rightEar
        let values = speechFreqs.compactMap { freq in
            data.first { $0.frequency == freq }?.thresholdDBHL
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

enum Ear: String, Codable, Sendable, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: "Left (AS)"
        case .right: "Right (AD)"
        }
    }

    var abbreviation: String {
        switch self {
        case .left: "AS"
        case .right: "AD"
        }
    }
}
