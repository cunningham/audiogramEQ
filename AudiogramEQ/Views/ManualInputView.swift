import SwiftUI

struct ManualInputView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedEar: Ear = .right

    var body: some View {
        @Bindable var state = appState

        HSplitView {
            // Left panel: input form
            VStack(alignment: .leading, spacing: 16) {
                Text("Manual Audiogram Entry")
                    .font(.title2.bold())

                Picker("Ear", selection: $selectedEar) {
                    ForEach(Ear.allCases) { ear in
                        Text(ear.displayName).tag(ear)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                if appState.audiogram.leftEar.isEmpty {
                    Button("Initialize with Normal Hearing") {
                        appState.audiogram = .blank()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(AudiometricFrequency.allCases, id: \.self) { freq in
                                FrequencyThresholdRow(
                                    frequency: freq,
                                    threshold: bindingForThreshold(frequency: freq),
                                    ear: selectedEar
                                )
                            }
                        }
                        .padding()
                    }
                }

                Spacer()

                HStack {
                    Button("Reset to Normal") {
                        appState.audiogram = .normal
                    }

                    Spacer()

                    Button("Generate EQ") {
                        generateEQ()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.hasAudiogramData)
                }
            }
            .padding()
            .frame(minWidth: 320, idealWidth: 400)

            // Right panel: audiogram chart
            AudiogramChartView(audiogram: appState.audiogram)
                .padding()
                .frame(minWidth: 400)
        }
    }

    private func bindingForThreshold(frequency: AudiometricFrequency) -> Binding<Double> {
        Binding<Double>(
            get: {
                let data = selectedEar == .left ? appState.audiogram.leftEar : appState.audiogram.rightEar
                return data.first { $0.frequency == frequency }?.thresholdDBHL ?? 0
            },
            set: { newValue in
                let clamped = min(max(newValue, -10), 120)
                switch selectedEar {
                case .left:
                    if let idx = appState.audiogram.leftEar.firstIndex(where: { $0.frequency == frequency }) {
                        appState.audiogram.leftEar[idx] = HearingThreshold(frequency: frequency, thresholdDBHL: clamped)
                    }
                case .right:
                    if let idx = appState.audiogram.rightEar.firstIndex(where: { $0.frequency == frequency }) {
                        appState.audiogram.rightEar[idx] = HearingThreshold(frequency: frequency, thresholdDBHL: clamped)
                    }
                }
            }
        )
    }

    private func generateEQ() {
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
        appState.selectedNavItem = .results
    }
}

struct FrequencyThresholdRow: View {
    let frequency: AudiometricFrequency
    @Binding var threshold: Double
    let ear: Ear

    var body: some View {
        HStack(spacing: 12) {
            Text(frequency.displayLabel)
                .font(.headline.monospacedDigit())
                .frame(width: 50, alignment: .trailing)

            Text("Hz")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: $threshold, in: -10...120, step: 5) {
                Text(frequency.displayLabel)
            }
            .tint(ear == .left ? .blue : .red)

            Text("\(Int(threshold)) dB")
                .font(.body.monospacedDigit())
                .frame(width: 60, alignment: .trailing)

            Stepper("", value: $threshold, in: -10...120, step: 5)
                .labelsHidden()
        }
    }
}
