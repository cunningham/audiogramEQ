import SwiftUI

@main
struct AudiogramEQApp: App {
    @State private var appState = AppState()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView(isPresented: $showOnboarding)
                }
                .onAppear {
                    if !hasCompletedOnboarding {
                        showOnboarding = true
                        hasCompletedOnboarding = true
                    }
                }
        }
        .defaultSize(width: 1100, height: 750)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Audiogram") {
                Button("Reset All Data") {
                    appState.reset()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Show Onboarding") {
                    showOnboarding = true
                }
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appState)
        }
        #endif
    }
}
