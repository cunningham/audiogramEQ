import Foundation

/// Combines the hearing compensation gain curve with optional device frequency response correction
/// to produce a unified target EQ curve.
struct EQCurveCombiner {

    /// Standard evaluation frequencies for the combined curve (log-spaced, 20 Hz to 20 kHz)
    static let standardFrequencies: [Double] = {
        let logMin = log10(20.0)
        let logMax = log10(20000.0)
        let count = 200
        return (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            return pow(10, logMin + t * (logMax - logMin))
        }
    }()

    /// Combine hearing compensation with device response correction.
    ///
    /// The logic:
    /// 1. Hearing compensation provides positive gain where hearing loss exists
    /// 2. Device response deviation shows where the device is louder/quieter than flat
    /// 3. We subtract the device deviation: if the device is already loud at a frequency,
    ///    we need less gain there; if it's quiet, we need more
    ///
    /// Final = hearing_compensation - device_deviation
    func combine(
        hearingCompensation: [FRPoint],
        deviceResponse: FrequencyResponseCurve
    ) -> [FRPoint] {
        let deviceDeviation = deviceResponse.deviationFromFlat()

        return Self.standardFrequencies.map { freq in
            let hearingGain = interpolate(at: freq, in: hearingCompensation)
            let deviceDev = interpolateDeviceDeviation(at: freq, in: deviceDeviation)

            let combinedGain = hearingGain - deviceDev
            return FRPoint(frequencyHz: freq, decibelSPL: combinedGain)
        }
    }

    /// Apply only hearing compensation (no device correction) resampled to standard grid
    func hearingCompensationOnly(_ compensation: [FRPoint]) -> [FRPoint] {
        Self.standardFrequencies.map { freq in
            let gain = interpolate(at: freq, in: compensation)
            return FRPoint(frequencyHz: freq, decibelSPL: gain)
        }
    }

    private func interpolate(at freq: Double, in points: [FRPoint]) -> Double {
        guard !points.isEmpty else { return 0 }
        guard points.count >= 2 else { return points[0].decibelSPL }

        if freq <= points.first!.frequencyHz { return points.first!.decibelSPL }
        if freq >= points.last!.frequencyHz { return points.last!.decibelSPL }

        let logFreq = log10(freq)

        for i in 0..<(points.count - 1) {
            let p0 = points[i]
            let p1 = points[i + 1]

            if freq >= p0.frequencyHz && freq <= p1.frequencyHz {
                let logF0 = log10(p0.frequencyHz)
                let logF1 = log10(p1.frequencyHz)
                let t = (logFreq - logF0) / (logF1 - logF0)
                return p0.decibelSPL + t * (p1.decibelSPL - p0.decibelSPL)
            }
        }
        return points.last!.decibelSPL
    }

    private func interpolateDeviceDeviation(at freq: Double, in deviation: [FRPoint]) -> Double {
        interpolate(at: freq, in: deviation)
    }
}
