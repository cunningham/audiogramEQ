import Foundation

/// Type of parametric EQ filter
enum FilterType: String, Codable, Sendable, CaseIterable, Identifiable {
    case peak = "Peak/Bell"
    case lowShelf = "Low Shelf"
    case highShelf = "High Shelf"
    case lowPass = "Low Pass"
    case highPass = "High Pass"

    var id: String { rawValue }
}

/// A single parametric EQ band
struct EQBand: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    var frequencyHz: Double
    var gainDB: Double
    var q: Double
    var filterType: FilterType
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        frequencyHz: Double,
        gainDB: Double,
        q: Double = 1.41,
        filterType: FilterType = .peak,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.frequencyHz = frequencyHz
        self.gainDB = gainDB
        self.q = q
        self.filterType = filterType
        self.isEnabled = isEnabled
    }

    /// Compute the gain contribution of this band at a given frequency
    /// Uses standard parametric EQ transfer function magnitude
    func gainAt(frequencyHz freq: Double) -> Double {
        guard isEnabled, abs(gainDB) > 0.01 else { return 0 }

        let w0 = 2.0 * Double.pi * frequencyHz
        let w = 2.0 * Double.pi * freq

        switch filterType {
        case .peak:
            // Bell/peak filter response approximation
            let logRatio = log2(freq / frequencyHz)
            let bandwidth = 1.0 / q
            let x = logRatio / (bandwidth / 2.0)
            return gainDB / (1.0 + x * x)

        case .lowShelf:
            let ratio = w / w0
            let transition = 1.0 / (1.0 + pow(ratio, 2.0 * q))
            return gainDB * transition

        case .highShelf:
            let transition = 1.0 / (1.0 + pow(w0 / max(w, 1), 2.0 * q))
            return gainDB * transition

        case .lowPass:
            let ratio = freq / frequencyHz
            if ratio <= 1.0 { return 0 }
            return -20.0 * log10(ratio) * q

        case .highPass:
            let ratio = frequencyHz / freq
            if ratio <= 1.0 { return 0 }
            return -20.0 * log10(ratio) * q
        }
    }
}

/// A complete EQ profile consisting of multiple bands
struct EQProfile: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    var bands: [EQBand]
    var globalGainDB: Double

    init(
        id: UUID = UUID(),
        bands: [EQBand] = [],
        globalGainDB: Double = 0
    ) {
        self.id = id
        self.bands = bands
        self.globalGainDB = globalGainDB
    }

    /// Total gain at a given frequency from all enabled bands plus global gain
    func totalGainAt(frequencyHz: Double) -> Double {
        let bandGain = bands.reduce(0.0) { $0 + $1.gainAt(frequencyHz: frequencyHz) }
        return bandGain + globalGainDB
    }

    /// Evaluate the EQ curve across a range of frequencies (log-spaced)
    func evaluateCurve(from minFreq: Double = 20, to maxFreq: Double = 20000, points: Int = 200) -> [FRPoint] {
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        return (0..<points).map { i in
            let t = Double(i) / Double(points - 1)
            let freq = pow(10, logMin + t * (logMax - logMin))
            return FRPoint(frequencyHz: freq, decibelSPL: totalGainAt(frequencyHz: freq))
        }
    }

    /// Sort bands by frequency
    mutating func sortBands() {
        bands.sort { $0.frequencyHz < $1.frequencyHz }
    }
}
