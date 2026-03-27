import Foundation
import Accelerate

/// Fits a parametric EQ curve to a target frequency response curve.
///
/// Algorithm:
/// 1. Identify peak/dip frequencies in the target curve
/// 2. Place EQ bands at those frequencies
/// 3. Iteratively optimize gain and Q for each band to minimize error
struct ParametricEQFitter {

    /// Fit parametric EQ bands to approximate the target curve
    func fit(
        targetCurve: [FRPoint],
        bandCount: Int = 10,
        maxGainDB: Double = 20.0,
        iterations: Int = 50,
        hasDeviceResponse: Bool = false
    ) -> EQProfile {
        guard !targetCurve.isEmpty else { return EQProfile() }

        // Step 1: Place initial bands at key frequencies
        var bands = placeBands(on: targetCurve, count: bandCount, maxGainDB: maxGainDB, hasDeviceResponse: hasDeviceResponse)

        // Step 2: Iteratively refine band parameters
        for _ in 0..<iterations {
            bands = refineBands(bands, target: targetCurve, maxGainDB: maxGainDB)
        }

        // Step 3: Apply gain limits and clean up
        bands = bands.map { band in
            var b = band
            b.gainDB = min(max(b.gainDB, -maxGainDB), maxGainDB)
            // Remove insignificant bands
            if abs(b.gainDB) < 0.5 { b.gainDB = 0; b.isEnabled = false }
            return b
        }
        .filter { $0.isEnabled }
        .sorted { $0.frequencyHz < $1.frequencyHz }

        // Compute pre-amp gain to prevent clipping
        let profile = EQProfile(bands: bands)
        let peakGain = targetCurve.map { profile.totalGainAt(frequencyHz: $0.frequencyHz) }.max() ?? 0
        let preampGain = peakGain > 0 ? -peakGain : 0

        return EQProfile(bands: bands, globalGainDB: preampGain)
    }

    /// Place initial bands at audiogram frequencies, plus extended range when device response is present
    private func placeBands(on target: [FRPoint], count: Int, maxGainDB: Double, hasDeviceResponse: Bool) -> [EQBand] {
        guard target.count >= 2 else { return [] }

        // Use audiogram frequencies as the primary band centers
        let audiogramFreqs = AudiometricFrequency.allCases.map { $0.rawValue }

        // Extended frequencies outside audiogram range for device response compensation
        let extendedFreqs: [Double] = hasDeviceResponse
            ? [20, 32, 63, 125, 10000, 12500, 16000, 20000]
            : []

        // Combine: audiogram freqs first, then extended freqs ranked by significance
        let coreFreqs = audiogramFreqs
        let rankedExtended = extendedFreqs.map { freq -> (Double, Double) in
            let gain = interpolateTarget(at: freq, in: target)
            return (freq, abs(gain))
        }.sorted { $0.1 > $1.1 }

        let candidateFreqs: [Double]
        if count <= coreFreqs.count {
            // Pick the most significant audiogram frequencies
            let ranked = coreFreqs.map { freq -> (Double, Double) in
                let gain = interpolateTarget(at: freq, in: target)
                return (freq, abs(gain))
            }.sorted { $0.1 > $1.1 }
            candidateFreqs = Array(ranked.prefix(count)).map(\.0).sorted()
        } else {
            // Use all audiogram frequencies, then fill with extended and evenly-spaced extras
            var freqs = coreFreqs

            // Add extended frequencies up to the band count
            for (freq, _) in rankedExtended {
                if freqs.count >= count { break }
                let minDist = freqs.map { abs(log10($0) - log10(freq)) }.min() ?? 1.0
                if minDist > 0.05 {
                    freqs.append(freq)
                }
            }

            // If still not enough, distribute remaining evenly across the target range
            if freqs.count < count {
                let remaining = count - freqs.count
                let logMin = log10(target.first!.frequencyHz)
                let logMax = log10(target.last!.frequencyHz)

                for i in 0..<remaining {
                    let t = Double(i + 1) / Double(remaining + 1)
                    let freq = pow(10, logMin + t * (logMax - logMin))
                    let minDist = freqs.map { abs(log10($0) - log10(freq)) }.min() ?? 1.0
                    if minDist > 0.05 {
                        freqs.append(freq)
                    }
                }
            }

            candidateFreqs = Array(freqs.prefix(count)).sorted()
        }

        return candidateFreqs.map { freq in
            let gain = interpolateTarget(at: freq, in: target)
            let clampedGain = min(max(gain, -maxGainDB), maxGainDB)
            return EQBand(
                frequencyHz: freq,
                gainDB: clampedGain,
                q: 1.41,
                filterType: .peak
            )
        }
    }

    /// Interpolate target curve value at a given frequency
    private func interpolateTarget(at freq: Double, in target: [FRPoint]) -> Double {
        guard let first = target.first, let last = target.last else { return 0 }
        if freq <= first.frequencyHz { return first.decibelSPL }
        if freq >= last.frequencyHz { return last.decibelSPL }

        let logFreq = log10(freq)
        for i in 0..<(target.count - 1) {
            let p0 = target[i]
            let p1 = target[i + 1]
            if freq >= p0.frequencyHz && freq <= p1.frequencyHz {
                let logF0 = log10(p0.frequencyHz)
                let logF1 = log10(p1.frequencyHz)
                let t = (logFreq - logF0) / (logF1 - logF0)
                return p0.decibelSPL + t * (p1.decibelSPL - p0.decibelSPL)
            }
        }
        return last.decibelSPL
    }

    /// Refine band parameters to reduce error against target
    private func refineBands(_ bands: [EQBand], target: [FRPoint], maxGainDB: Double) -> [EQBand] {
        var refined = bands

        for bandIdx in 0..<refined.count {
            // Compute current error without this band
            var testProfile = EQProfile(bands: refined)
            let currentBand = refined[bandIdx]

            // Temporarily disable this band
            refined[bandIdx].isEnabled = false
            testProfile = EQProfile(bands: refined)

            // Compute residual error at this band's frequency region
            let bandFreq = currentBand.frequencyHz
            let nearbyPoints = target.filter { point in
                let logDist = abs(log10(point.frequencyHz) - log10(bandFreq))
                return logDist < 0.5 // within ~0.5 decades
            }

            if !nearbyPoints.isEmpty {
                // Find the optimal gain for this band
                let residuals = nearbyPoints.map { point in
                    point.decibelSPL - testProfile.totalGainAt(frequencyHz: point.frequencyHz)
                }

                // Weighted average of residuals (weight by proximity)
                var totalWeight = 0.0
                var weightedResidual = 0.0

                for (i, point) in nearbyPoints.enumerated() {
                    let logDist = abs(log10(point.frequencyHz) - log10(bandFreq))
                    let weight = exp(-logDist * logDist / 0.05)
                    weightedResidual += residuals[i] * weight
                    totalWeight += weight
                }

                let targetGain = totalWeight > 0 ? weightedResidual / totalWeight : 0
                refined[bandIdx].gainDB = min(max(targetGain, -maxGainDB), maxGainDB)

                // Optimize Q: try a few values and pick the one with lowest error
                let qValues = [0.5, 0.71, 1.0, 1.41, 2.0, 3.0, 5.0]
                var bestQ = currentBand.q
                var bestError = Double.infinity

                for q in qValues {
                    refined[bandIdx].q = q
                    refined[bandIdx].isEnabled = true
                    let testProfile2 = EQProfile(bands: refined)

                    let error = nearbyPoints.reduce(0.0) { sum, point in
                        let diff = point.decibelSPL - testProfile2.totalGainAt(frequencyHz: point.frequencyHz)
                        return sum + diff * diff
                    }

                    if error < bestError {
                        bestError = error
                        bestQ = q
                    }
                }

                refined[bandIdx].q = bestQ
            }

            refined[bandIdx].isEnabled = true
        }

        return refined
    }
}
