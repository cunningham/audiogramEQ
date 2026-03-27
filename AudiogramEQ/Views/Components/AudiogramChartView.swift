import SwiftUI
import Charts

struct AudiogramChartView: View {
    let audiogram: Audiogram
    var showLegend: Bool = true

    private let frequencies = AudiometricFrequency.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audiogram")
                .font(.headline)

            Chart {
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
            .chartYScale(domain: -10...120)
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
            .chartXScale(domain: log2(Double(200))...log2(Double(10000)))
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

    private func legendItem(color: Color, symbol: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(label)
        }
    }
}
