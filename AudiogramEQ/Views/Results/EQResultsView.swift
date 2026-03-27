import SwiftUI
import Charts

struct EQResultsView: View {
    @Environment(AppState.self) private var appState
    @State private var exportFormat: ExportFormat = .autoEQ
    @State private var showingExport = false
    @State private var exportText = ""
    @State private var showCopiedToast = false

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 16) {
            HStack {
                Text("EQ Results")
                    .font(.title2.bold())
                Spacer()

                if appState.eqProfile != nil {
                    Button("Recalculate") {
                        recalculate()
                    }
                }
            }

            if let profile = appState.eqProfile {
                HSplitView {
                    // Left: EQ Curve visualization
                    VStack(alignment: .leading, spacing: 12) {
                        Text("EQ Curve")
                            .font(.headline)

                        EQCurveChartView(profile: profile)
                            .frame(minHeight: 300)

                        if profile.globalGainDB != 0 {
                            Text(String(format: "Pre-amp: %+.1f dB", profile.globalGainDB))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(minWidth: 400)

                    // Right: Band parameters
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Band Parameters")
                            .font(.headline)

                        Table(profile.bands.filter(\.isEnabled)) {
                            TableColumn("#") { band in
                                if let idx = profile.bands.firstIndex(where: { $0.id == band.id }) {
                                    Text("\(idx + 1)")
                                        .monospacedDigit()
                                }
                            }
                            .width(30)

                            TableColumn("Type") { band in
                                Text(band.filterType.rawValue)
                                    .font(.caption)
                            }
                            .width(70)

                            TableColumn("Freq (Hz)") { band in
                                Text(formatFrequency(band.frequencyHz))
                                    .monospacedDigit()
                            }
                            .width(80)

                            TableColumn("Gain (dB)") { band in
                                Text(String(format: "%+.1f", band.gainDB))
                                    .monospacedDigit()
                                    .foregroundStyle(band.gainDB >= 0 ? .green : .red)
                            }
                            .width(80)

                            TableColumn("Q") { band in
                                Text(String(format: "%.2f", band.q))
                                    .monospacedDigit()
                            }
                            .width(60)
                        }
                        .frame(minHeight: 200)

                        Divider()

                        // Export controls
                        HStack {
                            Picker("Format", selection: $exportFormat) {
                                ForEach(ExportFormat.allCases) { format in
                                    Text(format.rawValue).tag(format)
                                }
                            }
                            .frame(maxWidth: 200)

                            Button("Copy to Clipboard") {
                                copyToClipboard()
                            }

                            Button("Export File…") {
                                showingExport = true
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        // Save as preset
                        HStack {
                            Button("Save as Preset…") {
                                savePreset()
                            }
                        }

                        if showCopiedToast {
                            Text("✓ Copied to clipboard")
                                .font(.caption)
                                .foregroundStyle(.green)
                                .transition(.opacity)
                        }
                    }
                    .padding()
                    .frame(minWidth: 350)
                }
            } else {
                ContentUnavailableView {
                    Label("No EQ Profile Generated", systemImage: "waveform.path.ecg")
                } description: {
                    Text("Enter your audiogram data and click 'Generate EQ' to create compensation settings.")
                } actions: {
                    Button("Go to Manual Input") {
                        appState.selectedNavItem = .manualInput
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Spacer()
        }
        .padding()
        .fileExporter(
            isPresented: $showingExport,
            document: TextFileDocument(text: exportText),
            contentType: exportFormat == .json ? .json : .plainText,
            defaultFilename: "AudiogramEQ.\(exportFormat.fileExtension)"
        ) { result in
            if case .failure(let error) = result {
                print("Export failed: \(error)")
            }
        }
        .onChange(of: exportFormat) {
            if let profile = appState.eqProfile {
                exportText = ExportService().export(profile, format: exportFormat)
            }
        }
    }

    private func recalculate() {
        let compensation = HearingCompensationService()
        let targetCurve = compensation.computeTargetGainCurve(from: appState.audiogram)

        var combinedCurve = targetCurve
        if let deviceResponse = appState.deviceResponse {
            let combiner = EQCurveCombiner()
            combinedCurve = combiner.combine(
                hearingCompensation: targetCurve,
                deviceResponse: deviceResponse
            )
        }

        let fitter = ParametricEQFitter()
        appState.eqProfile = fitter.fit(
            targetCurve: combinedCurve,
            bandCount: appState.numberOfEQBands,
            maxGainDB: appState.maxGainDB
        )
    }

    private func copyToClipboard() {
        guard let profile = appState.eqProfile else { return }
        let text = ExportService().export(profile, format: exportFormat)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        withAnimation {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }

    private func savePreset() {
        guard let profile = appState.eqProfile else { return }
        let preset = EQPreset(
            name: "Preset \(Date().formatted(date: .abbreviated, time: .shortened))",
            audiogram: appState.audiogram,
            deviceResponseName: appState.deviceResponse?.name,
            eqProfile: profile
        )
        appState.presets.append(preset)
    }

    private func formatFrequency(_ freq: Double) -> String {
        if freq >= 1000 {
            return String(format: "%.1fk", freq / 1000)
        }
        return String(format: "%.0f", freq)
    }
}

struct EQCurveChartView: View {
    let profile: EQProfile

    var body: some View {
        let curvePoints = profile.evaluateCurve()

        Chart {
            // EQ curve
            ForEach(curvePoints) { point in
                LineMark(
                    x: .value("Frequency", log10(point.frequencyHz)),
                    y: .value("Gain (dB)", point.decibelSPL)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            // Zero reference line
            RuleMark(y: .value("Reference", 0))
                .foregroundStyle(.gray.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

            // Band markers
            ForEach(profile.bands.filter(\.isEnabled)) { band in
                PointMark(
                    x: .value("Frequency", log10(band.frequencyHz)),
                    y: .value("Gain (dB)", band.gainDB)
                )
                .foregroundStyle(band.gainDB >= 0 ? .green : .red)
                .symbolSize(50)
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
                AxisValueLabel {
                    if let db = value.as(Double.self) {
                        Text(String(format: "%+.0f", db))
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
    }
}
