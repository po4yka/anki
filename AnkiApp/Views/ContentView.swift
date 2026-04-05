import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailRouter()
        }
        .ankiErrorAlert($appState.collectionError)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
