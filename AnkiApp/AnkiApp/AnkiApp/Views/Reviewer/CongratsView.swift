import SwiftUI
import AppleBridgeCore
import AppleSharedUI

struct CongratsView: View {
    @Environment(AppState.self) private var appState
    let deckId: Int64
    let onReturn: () -> Void
    @State private var showingCustomStudy = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Congratulations!")
                .font(.largeTitle.bold())

            Text("You have finished this deck for now.")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Custom Study...") {
                    showingCustomStudy = true
                }

                Button("Return to Decks", action: onReturn)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .sheet(isPresented: $showingCustomStudy) {
            CustomStudyView(service: appState.service, deckId: deckId)
        }
    }
}
