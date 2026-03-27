import Foundation
import Vision
import AppKit

/// Service to extract audiogram threshold data from images using the Vision framework.
/// Uses VNRecognizeTextRequest for text detection and spatial analysis to map
/// detected axis labels and data values to audiometric thresholds.
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

        // Run text recognition with the modern async Vision API
        let textObservations = try await performTextRecognition(on: cgImage)

        guard !textObservations.isEmpty else {
            throw OCRError.noTextFound
        }

        // Parse recognized text with bounding boxes
        let textItems = extractTextItems(from: textObservations)

        // Try strategy 1: find tabular data (frequency row + value rows)
        if let tabularResults = parseTabularLayout(textItems), tabularResults.count >= 3 {
            return tabularResults
        }

        // Try strategy 2: find inline "freq: value" or "freq value" pairs
        if let inlineResults = parseInlinePairs(textItems), inlineResults.count >= 3 {
            return inlineResults
        }

        // Try strategy 3: spatial axis mapping (detect axis labels, map nearby values)
        if let spatialResults = parseSpatialLayout(textItems), spatialResults.count >= 3 {
            return spatialResults
        }

        throw OCRError.parsingFailed("Could not identify audiogram data in the image. Try manual point placement instead.")
    }

    // MARK: - Vision Text Recognition

    private func performTextRecognition(on cgImage: CGImage) async throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return request.results ?? []
    }

    // MARK: - Text Item Extraction

    private struct TextItem {
        let text: String
        let boundingBox: CGRect // normalized Vision coordinates (origin bottom-left)
        var midX: CGFloat { boundingBox.midX }
        var midY: CGFloat { boundingBox.midY }
    }

    private func extractTextItems(from observations: [VNRecognizedTextObservation]) -> [TextItem] {
        observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            return TextItem(text: candidate.string, boundingBox: obs.boundingBox)
        }
    }

    // MARK: - Strategy 1: Tabular Layout

    private func parseTabularLayout(_ items: [TextItem]) -> [HearingThreshold]? {
        let freqPatterns: [(String, AudiometricFrequency)] = [
            ("250", .hz250), ("500", .hz500), ("1000", .hz1000), ("1k", .hz1000),
            ("2000", .hz2000), ("2k", .hz2000), ("3000", .hz3000), ("3k", .hz3000),
            ("4000", .hz4000), ("4k", .hz4000), ("6000", .hz6000), ("6k", .hz6000),
            ("8000", .hz8000), ("8k", .hz8000)
        ]

        // Find frequency labels and their X positions
        var freqColumns: [(freq: AudiometricFrequency, x: CGFloat)] = []
        for item in items {
            let cleaned = item.text.trimmingCharacters(in: .whitespaces).lowercased()
                .replacingOccurrences(of: ",", with: "")
            for (pattern, freq) in freqPatterns {
                if cleaned == pattern.lowercased() && !freqColumns.contains(where: { $0.freq == freq }) {
                    freqColumns.append((freq, item.midX))
                    break
                }
            }
        }

        guard freqColumns.count >= 3 else { return nil }
        freqColumns.sort { $0.x < $1.x }

        // Find numeric values that are below the frequency header row and align with columns
        let freqRowY = freqColumns.map(\.x).isEmpty ? CGFloat(0) :
            items.filter { item in
                freqColumns.contains { abs($0.x - item.midX) < 0.03 }
            }.map(\.midY).max() ?? 0

        // Look for dB values in rows below the frequency labels
        var thresholds: [HearingThreshold] = []
        let columnTolerance: CGFloat = 0.04

        for item in items {
            guard item.midY < freqRowY - 0.01 else { continue } // below in Vision coords (Y flipped)
            let cleaned = item.text.trimmingCharacters(in: .whitespaces)
            guard let dbValue = Double(cleaned), dbValue >= -10, dbValue <= 120 else { continue }

            // Find which frequency column this aligns with
            if let match = freqColumns.min(by: { abs($0.x - item.midX) < abs($1.x - item.midX) }),
               abs(match.x - item.midX) < columnTolerance {
                if !thresholds.contains(where: { $0.frequency == match.freq }) {
                    thresholds.append(HearingThreshold(frequency: match.freq, thresholdDBHL: dbValue))
                }
            }
        }

        return thresholds.isEmpty ? nil : thresholds.sorted { $0.frequency < $1.frequency }
    }

    // MARK: - Strategy 2: Inline Pairs

    private func parseInlinePairs(_ items: [TextItem]) -> [HearingThreshold]? {
        var thresholds: [HearingThreshold] = []
        let allFreqs = AudiometricFrequency.allCases

        for item in items {
            let components = item.text.components(separatedBy: CharacterSet(charactersIn: ":=, \t"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard components.count >= 2 else { continue }

            for freq in allFreqs {
                let freqStr = String(Int(freq.rawValue))
                let freqKStr = freq.displayLabel.lowercased()

                if components[0].lowercased() == freqStr || components[0].lowercased() == freqKStr {
                    if let dbValue = Double(components[1]), dbValue >= -10, dbValue <= 120 {
                        thresholds.append(HearingThreshold(frequency: freq, thresholdDBHL: dbValue))
                    }
                }
            }
        }

        return thresholds.isEmpty ? nil : thresholds.sorted { $0.frequency < $1.frequency }
    }

    // MARK: - Strategy 3: Spatial Axis Mapping

    private func parseSpatialLayout(_ items: [TextItem]) -> [HearingThreshold]? {
        // Find dB labels on the Y axis (left side, small X values)
        var dbAnchors: [(db: Double, y: CGFloat)] = []
        var freqAnchors: [(freq: AudiometricFrequency, x: CGFloat)] = []

        let freqPatterns: [(String, AudiometricFrequency)] = [
            ("250", .hz250), ("500", .hz500), ("1000", .hz1000), ("1k", .hz1000),
            ("2000", .hz2000), ("2k", .hz2000), ("3000", .hz3000), ("3k", .hz3000),
            ("4000", .hz4000), ("4k", .hz4000), ("6000", .hz6000), ("6k", .hz6000),
            ("8000", .hz8000), ("8k", .hz8000)
        ]

        for item in items {
            let cleaned = item.text.trimmingCharacters(in: .whitespaces).lowercased()
                .replacingOccurrences(of: ",", with: "")

            // Frequency labels (typically along the top or bottom)
            for (pattern, freq) in freqPatterns {
                if cleaned == pattern.lowercased() && !freqAnchors.contains(where: { $0.freq == freq }) {
                    freqAnchors.append((freq, item.midX))
                    break
                }
            }

            // dB labels (typically along the left side)
            if let dbValue = Double(cleaned), dbValue >= -10, dbValue <= 120,
               dbValue.truncatingRemainder(dividingBy: 10) == 0, item.midX < 0.2 {
                dbAnchors.append((dbValue, item.midY))
            }
        }

        guard freqAnchors.count >= 3, dbAnchors.count >= 2 else { return nil }

        // Build coordinate mapping from anchor positions
        dbAnchors.sort { $0.y < $1.y }
        freqAnchors.sort { $0.x < $1.x }

        // In Vision coordinates, Y=0 is bottom, Y=1 is top
        // Audiogram: top = low dB (good hearing), bottom = high dB (hearing loss)
        // So higher Y in Vision = lower dB value
        let dbByY = dbAnchors.sorted { $0.y > $1.y } // highest Y first = lowest dB

        // Find numeric values that could be threshold annotations inside the chart area
        let chartMinX = (freqAnchors.first?.x ?? 0) - 0.02
        let chartMaxX = (freqAnchors.last?.x ?? 1) + 0.02
        let chartMinY = (dbAnchors.first?.y ?? 0) - 0.02
        let chartMaxY = (dbAnchors.last?.y ?? 1) + 0.02

        var thresholds: [HearingThreshold] = []

        for item in items {
            guard item.midX >= chartMinX, item.midX <= chartMaxX,
                  item.midY >= chartMinY, item.midY <= chartMaxY else { continue }

            let cleaned = item.text.trimmingCharacters(in: .whitespaces)
            guard let dbValue = Double(cleaned), dbValue >= -10, dbValue <= 120 else { continue }

            // Map X to nearest frequency
            if let nearestFreq = freqAnchors.min(by: { abs($0.x - item.midX) < abs($1.x - item.midX) }),
               abs(nearestFreq.x - item.midX) < 0.05 {
                if !thresholds.contains(where: { $0.frequency == nearestFreq.freq }) {
                    thresholds.append(HearingThreshold(frequency: nearestFreq.freq, thresholdDBHL: dbValue))
                }
            }
        }

        return thresholds.isEmpty ? nil : thresholds.sorted { $0.frequency < $1.frequency }
    }
}
