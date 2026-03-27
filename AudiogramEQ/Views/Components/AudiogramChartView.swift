import SwiftUI
import Charts

struct AudiogramChartView: View {
    let audiogram: Audiogram
    var showLegend: Bool = true
    /// When set, the chart supports click-to-plot for the specified ear
    var interactiveEar: Ear? = nil
    /// Callback when user clicks to place a point (frequency, dB HL)
    var onPlotPoint: ((AudiometricFrequency, Double) -> Void)? = nil

    private let frequencies = AudiometricFrequency.allCases
    private let yMin: Double = -10
    private let yMax: Double = 120
    private let xLogMin = log2(Double(200))
    private let xLogMax = log2(Double(10000))

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Audiogram")
                    .font(.headline)
                if interactiveEar != nil {
                    Text("— Click on the chart to place points")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            chartContent
                .frame(minHeight: 300)

            if showLegend {
                HStack(spacing: 20) {
                    legendItem(color: .red, symbol: "circle", label: "Right (AD)")
                    legendItem(color: .blue, symbol: "xmark", label: "Left (AS)")
                }
                .font(.caption)
            }

            if let rightPTA = audiogram.puretoneAverage(ear: .right),
               let leftPTA = audiogram.puretoneAverage(ear: .left) {
                HStack(spacing: 20) {
                    Text("PTA Right: \(Int(rightPTA)) dB")
                        .foregroundStyle(.red)
                    Text("PTA Left: \(Int(leftPTA)) dB")
                        .foregroundStyle(.blue)
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var chartContent: some View {
        let chart = Chart {
            // Right ear data (red circles)
            ForEach(audiogram.rightEar) { threshold in
                LineMark(
                    x: .value("Frequency", log2(threshold.frequency.rawValue)),
                    y: .value("dB HL", threshold.thresholdDBHL)
                )
                .foregroundStyle(.red)
                .interpolationMethod(.catmullRom)
                .symbol {
                    Circle()
                        .stroke(.red, lineWidth: 2)
                        .frame(width: 10, height: 10)
                }
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            // Left ear data (blue X marks)
            ForEach(audiogram.leftEar) { threshold in
                LineMark(
                    x: .value("Frequency", log2(threshold.frequency.rawValue)),
                    y: .value("dB HL", threshold.thresholdDBHL)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)
                .symbol {
                    Image(systemName: "xmark")
                        .font(.caption2.bold())
                        .foregroundStyle(.blue)
                }
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            // Normal hearing reference line at 25 dB
            RuleMark(y: .value("Normal Limit", 25))
                .foregroundStyle(.green.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                .annotation(position: .trailing, alignment: .leading) {
                    Text("Normal")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
        }
        .chartYScale(domain: yMin...yMax)
        .chartYAxis {
            AxisMarks(position: .leading, values: stride(from: -10, through: 120, by: 10).map { $0 }) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let db = value.as(Int.self) {
                        Text("\(db)")
                            .font(.caption2)
                    }
                }
            }
        }
        // Standard audiogram: higher dB HL = more hearing loss = lower on chart
        // Default Y axis direction already places 0 at top for this range
        .chartXScale(domain: xLogMin...xLogMax)
        .chartXAxis {
            AxisMarks(values: frequencies.map { log2($0.rawValue) }) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let logVal = value.as(Double.self) {
                        let freq = pow(2.0, logVal)
                        Text(AudiometricFrequency(rawValue: freq)?.displayLabel ?? "")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(.gray.opacity(0.05))
                .border(.gray.opacity(0.2))
        }

        if interactiveEar != nil {
            chart.chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            handleChartTap(at: location, proxy: proxy, geometry: geometry)
                        }
                }
            }
        } else {
            chart
        }
    }

    private func handleChartTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let onPlotPoint else { return }

        let plotFrame = geometry[proxy.plotFrame!]
        let relativeX = location.x - plotFrame.origin.x
        let relativeY = location.y - plotFrame.origin.y

        // Map pixel coordinates to data coordinates
        guard let logFreq: Double = proxy.value(atX: relativeX),
              let dbHL: Double = proxy.value(atY: relativeY) else { return }

        // Snap to nearest standard audiometric frequency
        let clickedFreq = pow(2.0, logFreq)
        guard let nearestFreq = frequencies.min(by: {
            abs(log2($0.rawValue) - log2(clickedFreq)) < abs(log2($1.rawValue) - log2(clickedFreq))
        }) else { return }

        // Snap dB to nearest 5 dB step, clamped to valid range
        let snappedDB = (dbHL / 5.0).rounded() * 5.0
        let clampedDB = min(max(snappedDB, yMin), yMax)

        onPlotPoint(nearestFreq, clampedDB)
    }

    private func legendItem(color: Color, symbol: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(label)
        }
    }
}
