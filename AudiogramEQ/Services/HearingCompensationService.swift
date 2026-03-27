import Foundation

/// Converts audiogram hearing thresholds into a target gain compensation curve.
///
/// Uses a simplified NAL-NL2-inspired prescription:
/// - Half-gain rule as baseline (apply half the hearing loss as gain)
/// - High-frequency emphasis factor for speech clarity
/// - Smoothing between standard audiometric frequencies
struct HearingCompensationService {

    struct GainPoint: Sendable {
        let frequencyHz: Double
        let gainDB: Double
    }

    /// Compute target gain curve from audiogram data.
    /// Returns an array of (frequency, gain) points for the worse ear at each frequency.
    func computeTargetGainCurve(from audiogram: Audiogram) -> [FRPoint] {
        let frequencies = AudiometricFrequency.allCases

        var gainPoints: [FRPoint] = []

        for freq in frequencies {
            let leftThreshold = audiogram.threshold(at: freq, ear: .left)
            let rightThreshold = audiogram.threshold(at: freq, ear: .right)

            // Use the better ear (lower threshold) for binaural listening compensation
            // or average if both available
            let threshold: Double
            if let left = leftThreshold, let right = rightThreshold {
                threshold = (left + right) / 2.0
            } else {
                threshold = leftThreshold ?? rightThreshold ?? 0
            }

            let gain = computeGain(threshold: threshold, frequencyHz: freq.rawValue)
            gainPoints.append(FRPoint(frequencyHz: freq.rawValue, decibelSPL: gain))
        }

        return gainPoints
    }

    /// Compute gain for a specific ear
    func computeTargetGainCurve(from audiogram: Audiogram, ear: Ear) -> [FRPoint] {
        let frequencies = AudiometricFrequency.allCases
        let data = ear == .left ? audiogram.leftEar : audiogram.rightEar

        return frequencies.compactMap { freq in
            guard let threshold = data.first(where: { $0.frequency == freq })?.thresholdDBHL else {
                return nil
            }
            let gain = computeGain(threshold: threshold, frequencyHz: freq.rawValue)
            return FRPoint(frequencyHz: freq.rawValue, decibelSPL: gain)
        }
    }

    /// Compute gain for a single frequency using the modified half-gain rule
    ///
    /// The NAL-NL2-inspired formula:
    /// 1. Half-gain rule: gain = hearing_loss * 0.5
    /// 2. High-frequency emphasis: boost frequencies above 1kHz slightly more
    /// 3. Compression knee: reduce gain for severe losses (>60 dB) to avoid over-amplification
    /// 4. Minimal correction: don't apply gain for thresholds below 15 dB HL (normal range)
    private func computeGain(threshold: Double, frequencyHz: Double) -> Double {
        // No correction needed for normal hearing
        guard threshold > 15 else { return 0 }

        let hearingLoss = threshold

        // Base gain: half-gain rule
        var gain = hearingLoss * 0.46

        // High-frequency emphasis: speech intelligibility boost above 1kHz
        if frequencyHz >= 1000 {
            let octavesAbove1k = log2(frequencyHz / 1000.0)
            gain += octavesAbove1k * 2.0
        }

        // Low-frequency reduction: reduce boom below 500Hz
        if frequencyHz < 500 {
            let octavesBelow500 = log2(500.0 / frequencyHz)
            gain -= octavesBelow500 * 3.0
        }

        // Compression for severe hearing loss (>60 dB HL)
        // Gradually reduce gain ratio for very high thresholds
        if hearingLoss > 60 {
            let excessLoss = hearingLoss - 60
            gain -= excessLoss * 0.1
        }

        // Don't apply negative gain (we're compensating, not attenuating)
        return max(gain, 0)
    }

    /// Interpolate the gain curve to arbitrary resolution for smooth display
    func interpolateGainCurve(_ points: [FRPoint], resolution: Int = 200) -> [FRPoint] {
        guard points.count >= 2 else { return points }

        let logMinFreq = log10(points.first!.frequencyHz)
        let logMaxFreq = log10(points.last!.frequencyHz)

        return (0..<resolution).map { i in
            let t = Double(i) / Double(resolution - 1)
            let logFreq = logMinFreq + t * (logMaxFreq - logMinFreq)
            let freq = pow(10, logFreq)

            // Find surrounding points and interpolate
            let db = interpolateValue(at: freq, in: points)
            return FRPoint(frequencyHz: freq, decibelSPL: db)
        }
    }

    private func interpolateValue(at freq: Double, in points: [FRPoint]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }

        if freq <= first.frequencyHz { return first.decibelSPL }
        if freq >= last.frequencyHz { return last.decibelSPL }

        let logFreq = log10(freq)

        for i in 0..<(points.count - 1) {
            let p0 = points[i]
            let p1 = points[i + 1]

            if freq >= p0.frequencyHz && freq <= p1.frequencyHz {
                let logF0 = log10(p0.frequencyHz)
                let logF1 = log10(p1.frequencyHz)
                let t = (logFreq - logF0) / (logF1 - logF0)

                // Cubic interpolation for smoother curves
                let t2 = t * t
                let t3 = t2 * t
                let smooth = 3 * t2 - 2 * t3 // Hermite smoothstep
                return p0.decibelSPL + smooth * (p1.decibelSPL - p0.decibelSPL)
            }
        }
        return last.decibelSPL
    }
}
