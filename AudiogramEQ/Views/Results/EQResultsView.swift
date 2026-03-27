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
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // EQ Curve visualization
                        VStack(alignment: .leading, spacing: 12) {
                            Text("EQ Curve")
                                .font(.headline)

                            EQCurveChartView(
                                profile: profile,
                                audiogram: appState.audiogram,
                                deviceResponse: appState.deviceResponse
                            )
                                .frame(minHeight: 250, idealHeight: 350)

                            if profile.globalGainDB != 0 {
                                Text(String(format: "Pre-amp: %+.1f dB", profile.globalGainDB))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        // Band parameters
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Band Parameters")
                                .font(.headline)

                            bandParameterGrid(profile: profile)

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
                                    if let profile = appState.eqProfile {
                                        exportText = ExportService().export(profile, format: exportFormat)
                                    }
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
                    }
                    .padding()
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
            maxGainDB: appState.maxGainDB,
            hasDeviceResponse: appState.deviceResponse != nil
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

    @ViewBuilder
    private func bandParameterGrid(profile: EQProfile) -> some View {
        let enabledBands = profile.bands.filter(\.isEnabled)
        Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
            // Header
            GridRow {
                Text("#").fontWeight(.semibold)
                Text("Type").fontWeight(.semibold)
                Text("Freq").fontWeight(.semibold)
                Text("Gain").fontWeight(.semibold)
                Text("Q").fontWeight(.semibold)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()
                .gridCellUnsizedAxes(.horizontal)

            ForEach(Array(enabledBands.enumerated()), id: \.element.id) { idx, band in
                GridRow {
                    Text("\(idx + 1)")
                        .monospacedDigit()
                    Text(band.filterType.rawValue)
                        .font(.caption)
                    Text(formatFrequency(band.frequencyHz))
                        .monospacedDigit()
                    Text(String(format: "%+.1f dB", band.gainDB))
                        .monospacedDigit()
                        .foregroundStyle(band.gainDB >= 0 ? .green : .red)
                    Text(String(format: "%.2f", band.q))
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EQCurveChartView: View {
    let profile: EQProfile
    var audiogram: Audiogram? = nil
    var deviceResponse: FrequencyResponseCurve? = nil

    private let audiogramLogTicks: [Double] = AudiometricFrequency.allCases.map { log10($0.rawValue) }

    var body: some View {
        let curvePoints = profile.evaluateCurve()
        let compensation = HearingCompensationService()

        VStack(alignment: .leading, spacing: 8) {
            Chart {
                // Audiogram hearing compensation curve
                if let audiogram = audiogram {
                    let targetCurve = compensation.computeTargetGainCurve(from: audiogram)
                    let smoothCurve = compensation.interpolateGainCurve(targetCurve)
                    ForEach(smoothCurve) { point in
                        LineMark(
                            x: .value("Frequency", log10(point.frequencyHz)),
                            y: .value("Gain (dB)", point.decibelSPL)
                        )
                        .foregroundStyle(by: .value("Series", "Audiogram Compensation"))
                    }
                }

                // Headphone response deviation
                if let deviceResponse = deviceResponse {
                    let deviation = deviceResponse.deviationFromFlat()
                    ForEach(deviation) { point in
                        LineMark(
                            x: .value("Frequency", log10(point.frequencyHz)),
                            y: .value("Gain (dB)", point.decibelSPL)
                        )
                        .foregroundStyle(by: .value("Series", "Headphone Response"))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }

                // Final EQ curve
                ForEach(curvePoints) { point in
                    LineMark(
                        x: .value("Frequency", log10(point.frequencyHz)),
                        y: .value("Gain (dB)", point.decibelSPL)
                    )
                    .foregroundStyle(by: .value("Series", "EQ Curve"))
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
            .chartForegroundStyleScale([
                "Audiogram Compensation": Color.purple,
                "Headphone Response": Color.orange,
                "EQ Curve": Color.blue
            ])
            .chartLegend(position: .bottom, alignment: .center, spacing: 12)
            .chartXAxis {
                AxisMarks(values: audiogramLogTicks) { value in
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
}
