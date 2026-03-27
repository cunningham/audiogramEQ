import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentStep = 0

    private let steps: [(icon: String, title: String, description: String)] = [
        (
            "ear.and.waveform",
            "Welcome to Audiogram EQ",
            "Convert your hearing test results into personalized EQ settings for your headphones or speakers."
        ),
        (
            "slider.horizontal.3",
            "Step 1: Enter Your Audiogram",
            "Input your hearing test data manually, or import it from an image or PDF of your audiogram."
        ),
        (
            "headphones",
            "Step 2: Add Device Response (Optional)",
            "Import your headphone or speaker's frequency response curve for even more accurate compensation. Supports AutoEQ-compatible CSV files."
        ),
        (
            "waveform.path.ecg",
            "Step 3: Get Your EQ Settings",
            "The app generates optimized parametric EQ settings that compensate for your hearing profile. Export them in multiple formats."
        )
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: steps[currentStep].icon)
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .frame(height: 80)

            Text(steps[currentStep].title)
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text(steps[currentStep].description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Spacer()

            // Step indicators
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { idx in
                    Circle()
                        .fill(idx == currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(40)
        .frame(width: 500, height: 400)
    }
}
