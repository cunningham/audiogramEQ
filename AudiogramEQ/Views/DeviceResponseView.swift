import SwiftUI
import UniformTypeIdentifiers
import Charts

struct DeviceResponseView: View {
    @Environment(AppState.self) private var appState
    @State private var isShowingFilePicker = false
    @State private var errorMessage: String?
    @State private var deviceType: DeviceType = .headphone

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Device Frequency Response")
                    .font(.title2.bold())
                Spacer()

                if appState.deviceResponse != nil {
                    Button("Clear") {
                        appState.deviceResponse = nil
                    }
                }
            }

            Text("Optionally import your headphone or speaker's frequency response curve to factor device characteristics into the EQ compensation.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Device Type", selection: $deviceType) {
                ForEach(DeviceType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)

            if let response = appState.deviceResponse {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(response.name, systemImage: "headphones")
                            .font(.headline)
                        Spacer()
                        Text("\(response.points.count) data points")
                            .foregroundStyle(.secondary)
                    }

                    // Frequency response chart
                    FrequencyResponseChartView(curve: response)
                        .frame(minHeight: 300)

                    // Deviation from flat
                    Text("Deviation from Flat Response")
                        .font(.headline)

                    let deviation = response.deviationFromFlat()
                    FrequencyResponseChartView(
                        curve: FrequencyResponseCurve(
                            name: "Deviation",
                            points: deviation
                        ),
                        referenceLineDB: 0
                    )
                    .frame(minHeight: 250)
                }
            } else {
                ContentUnavailableView {
                    Label("No Device Response Loaded", systemImage: "headphones")
                } description: {
                    Text("Import a frequency response CSV file (AutoEQ-compatible format) for your headphones or speakers.")
                } actions: {
                    Button("Import CSV File…") {
                        isShowingFilePicker = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Spacer()
        }
        .padding()
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            errorMessage = nil

            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Cannot access file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let parser = DeviceResponseParser()
            do {
                appState.deviceResponse = try parser.parse(from: url, deviceType: deviceType)
            } catch {
                errorMessage = "Import failed: \(error.localizedDescription)"
            }

        case .failure(let error):
            errorMessage = "File selection failed: \(error.localizedDescription)"
        }
    }
}

struct FrequencyResponseChartView: View {
    let curve: FrequencyResponseCurve
    var referenceLineDB: Double? = nil

    var body: some View {
        Chart {
            ForEach(curve.points) { point in
                LineMark(
                    x: .value("Frequency", log10(point.frequencyHz)),
                    y: .value("dB", point.decibelSPL)
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }

            if let refDB = referenceLineDB {
                RuleMark(y: .value("Reference", refDB))
                    .foregroundStyle(.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXAxis {
            let logTicks = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000].map { log10(Double($0)) }
            AxisMarks(values: logTicks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let logVal = value.as(Double.self) {
                        let freq = Int(pow(10, logVal))
                        Text(freq >= 1000 ? "\(freq/1000)k" : "\(freq)")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(.gray.opacity(0.05))
                .border(.gray.opacity(0.2))
        }
    }
}
