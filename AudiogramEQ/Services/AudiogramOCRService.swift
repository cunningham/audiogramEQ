import Foundation
import Vision
import AppKit

/// Service to extract audiogram threshold data from images using the Vision framework
struct AudiogramOCRService {

    enum OCRError: LocalizedError {
        case noImageData
        case cgImageConversionFailed
        case noTextFound
        case parsingFailed(String)

        var errorDescription: String? {
            switch self {
            case .noImageData: "No image data available."
            case .cgImageConversionFailed: "Could not convert image for analysis."
            case .noTextFound: "No text detected in the image."
            case .parsingFailed(let detail): "Could not parse audiogram data: \(detail)"
            }
        }
    }

    /// Extract hearing thresholds from an audiogram image
    func extractThresholds(from image: NSImage) async throws -> [HearingThreshold] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.cgImageConversionFailed
        }

        // Step 1: Run text recognition to find frequency and dB labels
        let textResults = try await recognizeText(in: cgImage)

        // Step 2: Detect potential data point markers
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // Step 3: Parse the detected text to find axis labels and values
        let chartBounds = inferChartBounds(from: textResults, imageSize: CGSize(width: imageWidth, height: imageHeight))

        // Step 4: Try to extract thresholds from text-based audiogram data
        let thresholds = parseThresholdsFromText(textResults, chartBounds: chartBounds)

        if thresholds.isEmpty {
            // Fallback: try to extract from tabular data in the text
            return try parseTabularAudiogramData(from: textResults)
        }

        return thresholds
    }

    private func recognizeText(in cgImage: CGImage) async throws -> [(String, CGRect)] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let results: [(String, CGRect)] = observations.compactMap { obs in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    return (candidate.string, obs.boundingBox)
                }
                continuation.resume(returning: results)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private struct ChartBounds {
        var minFreqX: CGFloat = 0
        var maxFreqX: CGFloat = 1
        var minDBY: CGFloat = 0
        var maxDBY: CGFloat = 1
        var minFreq: Double = 250
        var maxFreq: Double = 8000
        var minDB: Double = -10
        var maxDB: Double = 120
    }

    private func inferChartBounds(from texts: [(String, CGRect)], imageSize: CGSize) -> ChartBounds {
        var bounds = ChartBounds()

        // Look for frequency labels (250, 500, 1k, 2k, 4k, 8k)
        let freqPatterns: [(String, Double)] = [
            ("250", 250), ("500", 500), ("1000", 1000), ("1k", 1000),
            ("2000", 2000), ("2k", 2000), ("4000", 4000), ("4k", 4000),
            ("8000", 8000), ("8k", 8000)
        ]

        var freqPositions: [(Double, CGFloat)] = []
        var dbPositions: [(Double, CGFloat)] = []

        for (text, rect) in texts {
            let cleanText = text.trimmingCharacters(in: .whitespaces).lowercased()

            // Check frequency labels
            for (pattern, freq) in freqPatterns {
                if cleanText == pattern.lowercased() {
                    freqPositions.append((freq, rect.midX))
                }
            }

            // Check dB labels (numbers 0-120 typically on the Y axis)
            if let dbValue = Double(cleanText), dbValue >= -10, dbValue <= 120, dbValue.truncatingRemainder(dividingBy: 10) == 0 {
                dbPositions.append((dbValue, rect.midY))
            }
        }

        // Update bounds based on detected labels
        if let minFreqPos = freqPositions.min(by: { $0.1 < $1.1 }),
           let maxFreqPos = freqPositions.max(by: { $0.1 < $1.1 }) {
            bounds.minFreqX = minFreqPos.1
            bounds.maxFreqX = maxFreqPos.1
            bounds.minFreq = minFreqPos.0
            bounds.maxFreq = maxFreqPos.0
        }

        if let minDBPos = dbPositions.min(by: { $0.1 < $1.1 }),
           let maxDBPos = dbPositions.max(by: { $0.1 < $1.1 }) {
            bounds.minDBY = minDBPos.1
            bounds.maxDBY = maxDBPos.1
            bounds.minDB = minDBPos.0
            bounds.maxDB = maxDBPos.0
        }

        return bounds
    }

    private func parseThresholdsFromText(_ texts: [(String, CGRect)], chartBounds: ChartBounds) -> [HearingThreshold] {
        // This attempts to detect plotted points based on text annotations
        // Many audiograms have numerical values near the plotted points
        var thresholds: [HearingThreshold] = []

        let standardFreqs = AudiometricFrequency.allCases

        // Look for patterns like "250: 15" or frequency-value pairs
        for freq in standardFreqs {
            let freqStr = String(Int(freq.rawValue))
            // Find nearby dB values for each frequency column
            let freqTexts = texts.filter { text, rect in
                text.contains(freqStr)
            }

            for (text, _) in freqTexts {
                // Try to parse "freq: value" or "freq value" patterns
                let components = text.components(separatedBy: CharacterSet(charactersIn: ":, \t"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                if components.count >= 2,
                   let dbValue = Double(components.last!) {
                    thresholds.append(HearingThreshold(frequency: freq, thresholdDBHL: dbValue))
                }
            }
        }

        return thresholds
    }

    private func parseTabularAudiogramData(from texts: [(String, CGRect)]) throws -> [HearingThreshold] {
        // Try to find tabular data format where frequencies and values are listed
        var allNumbers: [(Double, CGRect)] = []

        for (text, rect) in texts {
            let cleaned = text.trimmingCharacters(in: .whitespaces)
            if let num = Double(cleaned) {
                allNumbers.append((num, rect))
            }
        }

        // Group by Y position (rows) with tolerance
        let rowTolerance: CGFloat = 0.02
        var rows: [[( Double, CGRect)]] = []

        for item in allNumbers.sorted(by: { $0.1.midY > $1.1.midY }) {
            if let rowIdx = rows.firstIndex(where: { row in
                abs(row.first!.1.midY - item.1.midY) < rowTolerance
            }) {
                rows[rowIdx].append(item)
            } else {
                rows.append([item])
            }
        }

        // Sort each row by X position
        rows = rows.map { $0.sorted { $0.1.midX < $1.1.midX } }

        // Try to match rows to frequency headers + values
        let standardFreqValues = Set(AudiometricFrequency.allCases.map { $0.rawValue })

        for row in rows {
            let values = row.map { $0.0 }
            // Check if this row contains frequency headers
            let freqMatches = values.filter { standardFreqValues.contains($0) }
            if freqMatches.count >= 4 {
                // Next row might contain the threshold values
                // This is a simplified heuristic
                continue
            }
        }

        throw OCRError.parsingFailed("Could not identify audiogram data in the image. Please use manual entry to verify the values.")
    }
}
