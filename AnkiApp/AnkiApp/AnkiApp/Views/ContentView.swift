import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            DetailRouter()
        }
        .ankiErrorAlert($appState.error)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
