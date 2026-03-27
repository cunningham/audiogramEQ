import Foundation

/// A single frequency-response measurement point
struct FRPoint: Codable, Sendable, Hashable, Identifiable {
    var id: Double { frequencyHz }
    let frequencyHz: Double
    let decibelSPL: Double
}

/// Frequency response curve for a headphone or speaker
struct FrequencyResponseCurve: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var deviceType: DeviceType
    var points: [FRPoint]
    var source: String

    init(
        id: UUID = UUID(),
        name: String = "",
        deviceType: DeviceType = .headphone,
        points: [FRPoint] = [],
        source: String = ""
    ) {
        self.id = id
        self.name = name
        self.deviceType = deviceType
        self.points = points.sorted { $0.frequencyHz < $1.frequencyHz }
        self.source = source
    }

    /// Interpolate dB value at an arbitrary frequency using linear interpolation on log-frequency scale
    func interpolatedDB(at frequencyHz: Double) -> Double? {
        guard points.count >= 2 else { return points.first?.decibelSPL }

        let logFreq = log10(frequencyHz)

        // Clamp to range
        if frequencyHz <= points.first!.frequencyHz { return points.first!.decibelSPL }
        if frequencyHz >= points.last!.frequencyHz { return points.last!.decibelSPL }

        // Find surrounding points
        for i in 0..<(points.count - 1) {
            let p0 = points[i]
            let p1 = points[i + 1]
            if frequencyHz >= p0.frequencyHz && frequencyHz <= p1.frequencyHz {
                let logF0 = log10(p0.frequencyHz)
                let logF1 = log10(p1.frequencyHz)
                let t = (logFreq - logF0) / (logF1 - logF0)
                return p0.decibelSPL + t * (p1.decibelSPL - p0.decibelSPL)
            }
        }
        return nil
    }

    /// Compute deviation from flat response (0 dB reference)
    /// Returns the curve's deviation: positive means louder than flat, negative means quieter
    func deviationFromFlat() -> [FRPoint] {
        guard !points.isEmpty else { return [] }
        let avgDB = points.map(\.decibelSPL).reduce(0, +) / Double(points.count)
        return points.map { FRPoint(frequencyHz: $0.frequencyHz, decibelSPL: $0.decibelSPL - avgDB) }
    }

    /// Frequency range of the measurement
    var frequencyRange: ClosedRange<Double>? {
        guard let first = points.first, let last = points.last else { return nil }
        return first.frequencyHz...last.frequencyHz
    }
}

enum DeviceType: String, Codable, Sendable, CaseIterable, Identifiable {
    case headphone = "Headphone"
    case speaker = "Speaker"
    case iem = "IEM"

    var id: String { rawValue }
}
