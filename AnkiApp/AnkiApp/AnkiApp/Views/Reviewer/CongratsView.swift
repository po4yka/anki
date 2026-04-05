import SwiftUI

struct CongratsView: View {
    let onReturn: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Congratulations!")
                .font(.largeTitle.bold())

            Text("You have finished this deck for now.")
                .foregroundStyle(.secondary)

            Button("Return to Decks", action: onReturn)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    CongratsView(onReturn: {})
}
