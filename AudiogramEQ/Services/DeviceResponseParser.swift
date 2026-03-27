import Foundation

/// Parses headphone/speaker frequency response data from CSV/text files.
/// Compatible with AutoEQ format and similar measurement data.
struct DeviceResponseParser {

    enum ParseError: LocalizedError {
        case emptyFile
        case invalidFormat(String)
        case insufficientData

        var errorDescription: String? {
            switch self {
            case .emptyFile: "File is empty."
            case .invalidFormat(let detail): "Invalid file format: \(detail)"
            case .insufficientData: "Not enough data points in the file."
            }
        }
    }

    /// Parse frequency response data from a text/CSV file.
    ///
    /// Supports formats:
    /// - AutoEQ: `frequency, raw, smoothed, error, ...` (comma or tab separated)
    /// - Simple two-column: `frequency dB` (space, tab, or comma separated)
    /// - Lines starting with # are comments
    func parse(from text: String, deviceName: String = "", deviceType: DeviceType = .headphone) throws -> FrequencyResponseCurve {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard !lines.isEmpty else { throw ParseError.emptyFile }

        var points: [FRPoint] = []
        var startLine = 0

        // Detect header row
        if let firstLine = lines.first,
           firstLine.lowercased().contains("frequency") || firstLine.lowercased().contains("freq") {
            startLine = 1
        }

        for i in startLine..<lines.count {
            let line = lines[i]

            // Split by comma, tab, or whitespace
            let components = line.components(separatedBy: CharacterSet(charactersIn: ",\t "))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard components.count >= 2,
                  let freq = Double(components[0]),
                  let db = Double(components[1]) else {
                continue
            }

            // Validate frequency range (20 Hz to 24 kHz)
            guard freq >= 20, freq <= 24000 else { continue }

            points.append(FRPoint(frequencyHz: freq, decibelSPL: db))
        }

        guard points.count >= 5 else { throw ParseError.insufficientData }

        return FrequencyResponseCurve(
            name: deviceName,
            deviceType: deviceType,
            points: points,
            source: "Imported file"
        )
    }

    /// Parse from a file URL
    func parse(from url: URL, deviceType: DeviceType = .headphone) throws -> FrequencyResponseCurve {
        let text = try String(contentsOf: url, encoding: .utf8)
        let name = url.deletingPathExtension().lastPathComponent
        return try parse(from: text, deviceName: name, deviceType: deviceType)
    }
}
