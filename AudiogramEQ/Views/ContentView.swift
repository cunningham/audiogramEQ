import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            Group {
                switch appState.selectedNavItem {
                case .manualInput:
                    ManualInputView()
                case .importAudiogram:
                    ImportAudiogramView()
                case .deviceResponse:
                    DeviceResponseView()
                case .results:
                    EQResultsView()
                case .presets:
                    PresetManagementView()
                case nil:
                    ContentUnavailableView(
                        "Select an item",
                        systemImage: "sidebar.left",
                        description: Text("Choose a section from the sidebar to get started.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
