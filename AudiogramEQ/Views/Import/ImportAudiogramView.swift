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

            if let image = importedImage {
                HStack(alignment: .top, spacing: 20) {
                    // Image preview
                    VStack {
                        Text("Imported Image")
                            .font(.headline)
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 500, maxHeight: 400)
                            .border(.secondary.opacity(0.3))
                    }

                    // OCR results
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Detected Thresholds")
                            .font(.headline)

                        if isProcessing {
                            ProgressView("Analyzing audiogram...")
                        } else if !ocrResults.isEmpty {
                            Picker("Ear", selection: $selectedEar) {
                                ForEach(Ear.allCases) { ear in
                                    Text(ear.displayName).tag(ear)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 250)

                            ForEach(ocrResults) { threshold in
                                HStack {
                                    Text(threshold.frequency.displayLabel)
                                        .frame(width: 50)
                                    Text("\(Int(threshold.thresholdDBHL)) dB HL")
                                    Spacer()
                                }
                            }

                            Button("Apply to \(selectedEar.displayName)") {
                                applyResults()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if let error = errorMessage {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                    .frame(minWidth: 200)
                }
            } else {
                ContentUnavailableView {
                    Label("No Audiogram Imported", systemImage: "doc.viewfinder")
                } description: {
                    Text("Import an audiogram image or PDF to automatically extract hearing threshold data.")
                } actions: {
                    Button("Choose File…") {
                        isShowingFilePicker = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Spacer()

            if importedImage != nil {
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

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            errorMessage = nil

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

        // Render first page as image
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

        Task {
            let ocrService = AudiogramOCRService()
            do {
                let results = try await ocrService.extractThresholds(from: image)
                await MainActor.run {
                    ocrResults = results
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "OCR failed: \(error.localizedDescription)"
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
    }
}
