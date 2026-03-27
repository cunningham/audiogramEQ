import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        TabView {
            // General settings
            Form {
                Section("EQ Parameters") {
                    Stepper("Number of EQ Bands: \(appState.numberOfEQBands)",
                            value: $state.numberOfEQBands, in: 5...31)

                    HStack {
                        Text("Max Gain Limit:")
                        Slider(value: $state.maxGainDB, in: 6...30, step: 1)
                        Text("\(Int(appState.maxGainDB)) dB")
                            .monospacedDigit()
                            .frame(width: 50)
                    }
                }

                Section("Export") {
                    Picker("Default Export Format", selection: $state.preferredExportFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            // About
            VStack(spacing: 16) {
                Image(systemName: "ear.and.waveform")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)

                Text("Audiogram EQ Converter")
                    .font(.title.bold())

                Text("Convert hearing test data into personalized EQ settings")
                    .foregroundStyle(.secondary)

                Text("Version 1.0")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .padding()
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 500, height: 350)
    }
}
