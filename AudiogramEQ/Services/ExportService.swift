import Foundation

/// Exports EQ profiles in various formats
struct ExportService {

    /// Export as human-readable parametric EQ text
    func exportAsParametricText(_ profile: EQProfile) -> String {
        var lines: [String] = []
        lines.append("Parametric EQ Settings")
        lines.append("=" .padding(toLength: 50, withPad: "=", startingAt: 0))
        lines.append("")

        if profile.globalGainDB != 0 {
            lines.append(String(format: "Preamp: %.1f dB", profile.globalGainDB))
            lines.append("")
        }

        for (i, band) in profile.bands.enumerated() where band.isEnabled {
            lines.append(String(format: "Band %d: %@ | Freq: %.0f Hz | Gain: %+.1f dB | Q: %.2f",
                                i + 1,
                                band.filterType.rawValue,
                                band.frequencyHz,
                                band.gainDB,
                                band.q))
        }

        return lines.joined(separator: "\n")
    }

    /// Export in AutoEQ-compatible ParametricEQ.txt format
    func exportAsAutoEQ(_ profile: EQProfile) -> String {
        var lines: [String] = []

        if profile.globalGainDB != 0 {
            lines.append(String(format: "Preamp: %.1f dB", profile.globalGainDB))
        }

        for (i, band) in profile.bands.enumerated() where band.isEnabled {
            let filterStr: String
            switch band.filterType {
            case .peak: filterStr = "PK"
            case .lowShelf: filterStr = "LSC"
            case .highShelf: filterStr = "HSC"
            case .lowPass: filterStr = "LP"
            case .highPass: filterStr = "HP"
            }
            lines.append(String(format: "Filter %d: ON %@ Fc %.0f Hz Gain %.1f dB Q %.3f",
                                i + 1, filterStr, band.frequencyHz, band.gainDB, band.q))
        }

        return lines.joined(separator: "\n")
    }

    /// Export as JSON
    func exportAsJSON(_ profile: EQProfile) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(profile),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// Export in the specified format
    func export(_ profile: EQProfile, format: ExportFormat) -> String {
        switch format {
        case .parametricText: exportAsParametricText(profile)
        case .autoEQ: exportAsAutoEQ(profile)
        case .json: exportAsJSON(profile)
        }
    }
}
