import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        List(selection: $state.selectedNavItem) {
            ForEach(NavigationSection.allCases, id: \.self) { section in
                Section(section.rawValue) {
                    ForEach(NavigationItem.allCases.filter { $0.section == section }) { item in
                        Label(item.rawValue, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .toolbar {
            ToolbarItem {
                Button {
                    appState.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .help("Reset all data")
            }
        }
    }
}
