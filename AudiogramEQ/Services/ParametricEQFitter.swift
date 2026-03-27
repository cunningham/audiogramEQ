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
        iterations: Int = 50
    ) -> EQProfile {
        guard !targetCurve.isEmpty else { return EQProfile() }

        // Step 1: Find the most significant peaks and dips in the target curve
        var bands = placeBands(on: targetCurve, count: bandCount, maxGainDB: maxGainDB)

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

    /// Place initial bands at the most significant deviation frequencies
    private func placeBands(on target: [FRPoint], count: Int, maxGainDB: Double) -> [EQBand] {
        guard target.count >= 2 else { return [] }

        // Find local extrema (peaks and dips)
        var extrema: [(index: Int, magnitude: Double)] = []

        for i in 1..<(target.count - 1) {
            let prev = target[i - 1].decibelSPL
            let curr = target[i].decibelSPL
            let next = target[i + 1].decibelSPL

            let isPeak = curr > prev && curr > next
            let isDip = curr < prev && curr < next
            let isSignificant = abs(curr) > 1.0

            if (isPeak || isDip) && isSignificant {
                extrema.append((i, abs(curr)))
            }
        }

        // Sort by magnitude (most significant first)
        extrema.sort { $0.magnitude > $1.magnitude }

        // Take top N extrema, ensuring minimum frequency spacing
        var selectedIndices: [Int] = []
        let minLogSpacing = 0.15 // minimum ~0.15 octave spacing

        for ext in extrema {
            let logFreq = log10(target[ext.index].frequencyHz)
            let tooClose = selectedIndices.contains { idx in
                abs(log10(target[idx].frequencyHz) - logFreq) < minLogSpacing
            }
            if !tooClose {
                selectedIndices.append(ext.index)
            }
            if selectedIndices.count >= count { break }
        }

        // If we don't have enough extrema, distribute remaining bands evenly
        if selectedIndices.count < count {
            let remaining = count - selectedIndices.count
            let logMin = log10(target.first!.frequencyHz)
            let logMax = log10(target.last!.frequencyHz)

            for i in 0..<remaining {
                let t = Double(i + 1) / Double(remaining + 1)
                let logFreq = logMin + t * (logMax - logMin)
                let freq = pow(10, logFreq)

                // Find closest point
                if let closest = target.enumerated().min(by: {
                    abs($0.element.frequencyHz - freq) < abs($1.element.frequencyHz - freq)
                }) {
                    if !selectedIndices.contains(closest.offset) {
                        selectedIndices.append(closest.offset)
                    }
                }
            }
        }

        // Create bands from selected points
        return selectedIndices.map { idx in
            let point = target[idx]
            let gain = min(max(point.decibelSPL, -maxGainDB), maxGainDB)
            return EQBand(
                frequencyHz: point.frequencyHz,
                gainDB: gain,
                q: 1.41,
                filterType: .peak
            )
        }
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
