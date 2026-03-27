import SwiftUI
import UniformTypeIdentifiers
import Charts

struct DeviceResponseView: View {
    @Environment(AppState.self) private var appState
    @State private var isShowingFilePicker = false
    @State private var errorMessage: String?
    @State private var deviceType: DeviceType = .headphone
    @State private var sourceTab: SourceTab = .autoEQ

    enum SourceTab: String, CaseIterable {
        case autoEQ = "AutoEQ Database"
        case localFile = "Import File"
    }

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

            Text("Optionally load your headphone or speaker's frequency response curve to factor device characteristics into the EQ compensation.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let response = appState.deviceResponse {
                DeviceResponseLoadedView(response: response)
            } else {
                Picker("Device Type", selection: $deviceType) {
                    ForEach(DeviceType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)

                Picker("Source", selection: $sourceTab) {
                    ForEach(SourceTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)

                switch sourceTab {
                case .autoEQ:
                    AutoEQBrowserView(deviceType: deviceType)
                case .localFile:
                    localFileImportView
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

    private var localFileImportView: some View {
        ContentUnavailableView {
            Label("Import from File", systemImage: "doc.badge.plus")
        } description: {
            Text("Import a frequency response CSV or text file (AutoEQ-compatible format).")
        } actions: {
            Button("Choose File…") {
                isShowingFilePicker = true
            }
            .buttonStyle(.borderedProminent)
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

// MARK: - Loaded Device Response Display

private struct DeviceResponseLoadedView: View {
    let response: FrequencyResponseCurve

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(response.name, systemImage: "headphones")
                        .font(.headline)
                    Spacer()
                    Text("\(response.points.count) data points")
                        .foregroundStyle(.secondary)
                }

                if !response.source.isEmpty {
                    Text(response.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                FrequencyResponseChartView(curve: response)
                    .frame(minHeight: 300)

                Text("Deviation from Flat Response")
                    .font(.headline)

                let deviation = response.deviationFromFlat()
                FrequencyResponseChartView(
                    curve: FrequencyResponseCurve(name: "Deviation", points: deviation),
                    referenceLineDB: 0
                )
                .frame(minHeight: 250)
            }
        }
    }
}

// MARK: - AutoEQ Browser

struct AutoEQBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var autoEQ = AutoEQService()
    @State private var searchText = ""
    @State private var selectedEntry: AutoEQService.AutoEQEntry?
    @State private var isDownloading = false
    @State private var downloadError: String?
    let deviceType: DeviceType

    var body: some View {
        VStack(spacing: 12) {
            // Attribution
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                Text("Headphone measurements from")
                Link("AutoEQ by Jaakko Pasanen",
                     destination: URL(string: "https://github.com/jaakkopasanen/AutoEq")!)
                Text("(MIT License)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search headphones…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchText) { _, newValue in
                        autoEQ.search(newValue)
                    }

                if autoEQ.headphoneIndex.isEmpty && !autoEQ.isLoading {
                    Button("Load Database") {
                        Task { await autoEQ.fetchIndex() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if autoEQ.isLoading {
                ProgressView("Loading AutoEQ database…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = autoEQ.errorMessage {
                ContentUnavailableView {
                    Label("Load Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await autoEQ.fetchIndex() }
                    }
                }
            } else if autoEQ.headphoneIndex.isEmpty {
                ContentUnavailableView {
                    Label("AutoEQ Database", systemImage: "headphones")
                } description: {
                    Text("Browse thousands of headphone frequency response measurements. Click 'Load Database' to get started.")
                }
            } else {
                // Results list
                HStack(alignment: .top, spacing: 16) {
                    List(autoEQ.searchResults, selection: $selectedEntry) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.body)
                            Text(entry.source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(entry)
                    }
                    .frame(minWidth: 300)

                    // Detail / download pane
                    VStack(spacing: 16) {
                        if let entry = selectedEntry {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(entry.name)
                                    .font(.title3.bold())
                                Text("Source: \(entry.source)")
                                    .foregroundStyle(.secondary)
                                Text(entry.attribution)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if isDownloading {
                                ProgressView("Downloading…")
                            } else {
                                Button("Use This Measurement") {
                                    downloadAndApply(entry)
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            if let error = downloadError {
                                Text(error)
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        } else {
                            ContentUnavailableView(
                                "Select a Headphone",
                                systemImage: "arrow.left",
                                description: Text("Choose a headphone from the list to view details and import its measurements.")
                            )
                        }
                        Spacer()
                    }
                    .frame(minWidth: 250)
                }

                Text("\(autoEQ.searchResults.count) of \(autoEQ.headphoneIndex.count) results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .task {
            if autoEQ.headphoneIndex.isEmpty {
                await autoEQ.fetchIndex()
            }
        }
    }

    private func downloadAndApply(_ entry: AutoEQService.AutoEQEntry) {
        isDownloading = true
        downloadError = nil

        Task {
            do {
                var curve = try await autoEQ.fetchFrequencyResponse(for: entry)
                curve.deviceType = deviceType
                appState.deviceResponse = curve
                isDownloading = false
            } catch {
                downloadError = "Download failed: \(error.localizedDescription)"
                isDownloading = false
            }
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
