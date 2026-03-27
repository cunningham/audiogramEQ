import SwiftUI
import UniformTypeIdentifiers

struct ImportAudiogramView: View {
    @Environment(AppState.self) private var appState
    @State private var importMode: ImportMode = .image
    @State private var importedImage: NSImage?
    @State private var isShowingFilePicker = false
    @State private var ocrResults: [HearingThreshold] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var selectedEar: Ear = .right
    @State private var showManualOverlay = false
    @State private var ocrFailed = false

    enum ImportMode: String, CaseIterable {
        case image = "Image"
        case pdf = "PDF"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Import Audiogram")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Import From", selection: $importMode) {
                ForEach(ImportMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            if showManualOverlay, let image = importedImage {
                // Manual overlay mode — user places points on the image
                AudiogramImageOverlayView(
                    image: image,
                    ear: selectedEar,
                    onComplete: { thresholds in
                        ocrResults = thresholds
                        showManualOverlay = false
                    },
                    onCancel: {
                        showManualOverlay = false
                    }
                )
            } else if let image = importedImage {
                importedImageView(image: image)
            } else {
                emptyStateView
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Spacer()

            if importedImage != nil && !showManualOverlay {
                HStack {
                    Button("Choose Different File…") {
                        isShowingFilePicker = true
                    }
                    Spacer()
                }
            }
        }
        .padding()
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: importMode == .image
                ? [.image, .png, .jpeg, .tiff]
                : [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    @ViewBuilder
    private func importedImageView(image: NSImage) -> some View {
        HStack(alignment: .top, spacing: 20) {
            // Image preview
            VStack {
                Text("Imported Image")
                    .font(.headline)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 400)
                    .border(.secondary.opacity(0.3))
            }

            // OCR results / controls
            VStack(alignment: .leading, spacing: 12) {
                Picker("Ear", selection: $selectedEar) {
                    ForEach(Ear.allCases) { ear in
                        Text(ear.displayName).tag(ear)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 250)

                if isProcessing {
                    ProgressView("Analyzing audiogram…")
                } else if ocrFailed {
                    // OCR failed — offer manual overlay
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Automatic detection failed", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        Text("You can manually place data points on the image by clicking where each frequency threshold appears on the audiogram.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Button("Place Points Manually") {
                            showManualOverlay = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Retry OCR") {
                            runOCR(on: image)
                        }
                    }
                } else if !ocrResults.isEmpty {
                    Text("Detected Thresholds")
                        .font(.headline)

                    ForEach(ocrResults) { threshold in
                        HStack {
                            Text(threshold.frequency.displayLabel)
                                .frame(width: 50)
                                .monospacedDigit()
                            Text("\(Int(threshold.thresholdDBHL)) dB HL")
                            Spacer()
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Apply to \(selectedEar.displayName)") {
                            applyResults()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Adjust Manually") {
                            showManualOverlay = true
                        }
                    }
                } else {
                    // No results yet, OCR hasn't run or returned empty
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No thresholds detected yet.")
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Run OCR Analysis") {
                                runOCR(on: image)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Place Points Manually") {
                                showManualOverlay = true
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 250)
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Audiogram Imported", systemImage: "doc.viewfinder")
        } description: {
            Text("Import an audiogram image or PDF to automatically extract hearing threshold data, or manually place points on the image.")
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
            ocrFailed = false
            ocrResults = []

            if importMode == .pdf {
                importPDF(from: url)
            } else {
                importImage(from: url)
            }

        case .failure(let error):
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func importImage(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Cannot access file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let image = NSImage(contentsOf: url) else {
            errorMessage = "Could not load image."
            return
        }
        importedImage = image
        runOCR(on: image)
    }

    private func importPDF(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Cannot access file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let pdfDoc = PDFDocumentLoader.load(from: url) else {
            errorMessage = "Could not load PDF."
            return
        }

        if let image = pdfDoc.renderFirstPage() {
            importedImage = image
            runOCR(on: image)
        } else {
            errorMessage = "Could not render PDF page."
        }
    }

    private func runOCR(on image: NSImage) {
        isProcessing = true
        ocrResults = []
        ocrFailed = false

        Task {
            let ocrService = AudiogramOCRService()
            do {
                let results = try await ocrService.extractThresholds(from: image)
                await MainActor.run {
                    if results.isEmpty {
                        ocrFailed = true
                    } else {
                        ocrResults = results
                    }
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    ocrFailed = true
                    errorMessage = "OCR analysis could not extract data. Use manual placement instead."
                    isProcessing = false
                }
            }
        }
    }

    private func applyResults() {
        switch selectedEar {
        case .left:
            if appState.audiogram.leftEar.isEmpty {
                appState.audiogram = .blank()
            }
            for threshold in ocrResults {
                if let idx = appState.audiogram.leftEar.firstIndex(where: { $0.frequency == threshold.frequency }) {
                    appState.audiogram.leftEar[idx] = threshold
                }
            }
        case .right:
            if appState.audiogram.rightEar.isEmpty {
                appState.audiogram = .blank()
            }
            for threshold in ocrResults {
                if let idx = appState.audiogram.rightEar.firstIndex(where: { $0.frequency == threshold.frequency }) {
                    appState.audiogram.rightEar[idx] = threshold
                }
            }
        }
        appState.selectedNavItem = .manualInput
    }
}

// MARK: - Manual Image Overlay

/// Allows the user to click directly on an audiogram image to place threshold data points.
/// The view overlays a coordinate grid on the image and maps clicks to frequency/dB values.
struct AudiogramImageOverlayView: View {
    let image: NSImage
    let ear: Ear
    let onComplete: ([HearingThreshold]) -> Void
    let onCancel: () -> Void

    @State private var placedPoints: [AudiometricFrequency: CGPoint] = [:]
    @State private var currentFrequency: AudiometricFrequency = .hz250
    @State private var calibrationStep: CalibrationStep = .topLeft
    @State private var topLeftAnchor: CGPoint?
    @State private var bottomRightAnchor: CGPoint?
    @State private var imageSize: CGSize = .zero

    // Calibration: user marks two corners of the audiogram chart area
    enum CalibrationStep {
        case topLeft       // Mark the top-left corner of chart (lowest freq, best hearing)
        case bottomRight   // Mark the bottom-right corner (highest freq, worst hearing)
        case placing       // Placing data points
    }

    // Audiogram chart bounds (standard clinical format)
    private let chartMinFreq = 250.0    // Hz
    private let chartMaxFreq = 8000.0   // Hz
    private let chartMinDB = -10.0      // dB HL (top of chart)
    private let chartMaxDB = 120.0      // dB HL (bottom of chart)

    private var frequencies: [AudiometricFrequency] { AudiometricFrequency.allCases }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Manual Point Placement")
                    .font(.title3.bold())
                Spacer()
                Button("Cancel") { onCancel() }
            }

            instructionBar

            GeometryReader { geometry in
                let imageAspect = image.size.width / image.size.height
                let containerAspect = geometry.size.width / geometry.size.height
                let fittedSize: CGSize = {
                    if imageAspect > containerAspect {
                        let w = geometry.size.width
                        return CGSize(width: w, height: w / imageAspect)
                    } else {
                        let h = geometry.size.height
                        return CGSize(width: h * imageAspect, height: h)
                    }
                }()
                let offsetX = (geometry.size.width - fittedSize.width) / 2
                let offsetY = (geometry.size.height - fittedSize.height) / 2

                ZStack(alignment: .topLeading) {
                    // Background image — fixed size, no re-layout
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: fittedSize.width, height: fittedSize.height)

                    // Calibration anchors
                    if let tl = topLeftAnchor {
                        anchorMarker(at: tl, color: .green, label: "TL")
                    }
                    if let br = bottomRightAnchor {
                        anchorMarker(at: br, color: .green, label: "BR")
                    }

                    // Grid overlay (after calibration)
                    if calibrationStep == .placing, let tl = topLeftAnchor, let br = bottomRightAnchor {
                        gridOverlay(topLeft: tl, bottomRight: br, in: fittedSize)
                    }

                    // Placed data points
                    ForEach(Array(placedPoints.keys), id: \.self) { freq in
                        if let point = placedPoints[freq] {
                            dataPointMarker(at: point, frequency: freq)
                        }
                    }

                    // Click handler
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            handleTap(at: location)
                        }
                }
                .frame(width: fittedSize.width, height: fittedSize.height)
                .offset(x: offsetX, y: offsetY)
            }
            .frame(maxHeight: .infinity)
            .border(Color.secondary.opacity(0.3))

            if calibrationStep == .placing {
                placingControls
            }
        }
    }

    private var instructionBar: some View {
        HStack {
            Image(systemName: instructionIcon)
                .foregroundStyle(Color.accentColor)
            Text(instructionText)
                .font(.callout)
            Spacer()
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var instructionIcon: String {
        switch calibrationStep {
        case .topLeft: "scope"
        case .bottomRight: "scope"
        case .placing: "hand.point.up.left"
        }
    }

    private var instructionText: String {
        switch calibrationStep {
        case .topLeft:
            "Click the TOP-LEFT corner of the audiogram chart area (where 250 Hz and -10 dB intersect)."
        case .bottomRight:
            "Click the BOTTOM-RIGHT corner of the audiogram chart area (where 8000 Hz and 120 dB intersect)."
        case .placing:
            "Click on the chart where the \(ear == .left ? "X" : "O") marker for \(currentFrequency.displayLabel) Hz is located. Press Skip to skip a frequency."
        }
    }

    private var placingControls: some View {
        HStack {
            Text("Placing: \(currentFrequency.displayLabel) Hz")
                .font(.headline)
                .monospacedDigit()

            Spacer()

            // Frequency navigation
            Button("Skip") {
                advanceFrequency()
            }

            if let lastFreq = frequencies.last(where: { placedPoints[$0] != nil }) {
                Button("Undo \(lastFreq.displayLabel)") {
                    placedPoints.removeValue(forKey: lastFreq)
                    currentFrequency = lastFreq
                }
            }

            Spacer()

            Text("\(placedPoints.count)/\(frequencies.count) placed")
                .foregroundStyle(.secondary)

            Button("Done") {
                finalize()
            }
            .buttonStyle(.borderedProminent)
            .disabled(placedPoints.isEmpty)
        }
    }

    private func handleTap(at location: CGPoint) {
        switch calibrationStep {
        case .topLeft:
            topLeftAnchor = location
            calibrationStep = .bottomRight

        case .bottomRight:
            bottomRightAnchor = location
            calibrationStep = .placing

        case .placing:
            placedPoints[currentFrequency] = location
            advanceFrequency()
        }
    }

    private func advanceFrequency() {
        guard let currentIdx = frequencies.firstIndex(of: currentFrequency) else { return }
        let nextIdx = currentIdx + 1
        if nextIdx < frequencies.count {
            currentFrequency = frequencies[nextIdx]
        }
        // If we're past the last frequency, stay on it (user can press Done)
    }

    private func finalize() {
        guard let tl = topLeftAnchor, let br = bottomRightAnchor else { return }

        var thresholds: [HearingThreshold] = []

        for (freq, point) in placedPoints {
            // Map pixel position to dB HL using the calibration anchors
            let chartWidth = br.x - tl.x
            let chartHeight = br.y - tl.y

            guard chartWidth > 0, chartHeight > 0 else { continue }

            // Y maps linearly: tl.y = chartMinDB (-10), br.y = chartMaxDB (120)
            let yFraction = (point.y - tl.y) / chartHeight
            let dbHL = chartMinDB + yFraction * (chartMaxDB - chartMinDB)
            let clampedDB = (min(max(dbHL, chartMinDB), chartMaxDB) / 5.0).rounded() * 5.0

            thresholds.append(HearingThreshold(frequency: freq, thresholdDBHL: clampedDB))
        }

        thresholds.sort { $0.frequency < $1.frequency }
        onComplete(thresholds)
    }

    // MARK: - Visual elements

    private func anchorMarker(at point: CGPoint, color: Color, label: String) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 20, height: 20)
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: 20, height: 20)
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(color)
                .offset(y: -16)
        }
        .position(point)
    }

    private func dataPointMarker(at point: CGPoint, frequency: AudiometricFrequency) -> some View {
        ZStack {
            if ear == .right {
                Circle()
                    .stroke(.red, lineWidth: 2)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }
            Text(frequency.displayLabel)
                .font(.system(size: 9).bold())
                .foregroundStyle(ear == .right ? .red : .blue)
                .offset(y: 14)
        }
        .position(point)
    }

    private func gridOverlay(topLeft tl: CGPoint, bottomRight br: CGPoint, in size: CGSize) -> some View {
        Canvas { context, _ in
            let chartRect = CGRect(
                x: tl.x, y: tl.y,
                width: br.x - tl.x, height: br.y - tl.y
            )

            // Draw frequency grid lines
            for freq in frequencies {
                let logMin = log2(chartMinFreq)
                let logMax = log2(chartMaxFreq)
                let logFreq = log2(freq.rawValue)
                let xFraction = (logFreq - logMin) / (logMax - logMin)
                let x = chartRect.minX + xFraction * chartRect.width

                var path = Path()
                path.move(to: CGPoint(x: x, y: chartRect.minY))
                path.addLine(to: CGPoint(x: x, y: chartRect.maxY))
                context.stroke(path, with: .color(.cyan.opacity(0.3)), lineWidth: 0.5)
            }

            // Draw dB grid lines every 10 dB
            for db in stride(from: chartMinDB, through: chartMaxDB, by: 10) {
                let yFraction = (db - chartMinDB) / (chartMaxDB - chartMinDB)
                let y = chartRect.minY + yFraction * chartRect.height

                var path = Path()
                path.move(to: CGPoint(x: chartRect.minX, y: y))
                path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
                context.stroke(path, with: .color(.cyan.opacity(0.2)), lineWidth: 0.5)
            }

            // Chart border
            context.stroke(Path(chartRect), with: .color(.cyan.opacity(0.5)), lineWidth: 1)
        }
    }
}
