import SwiftUI

struct AnkiErrorAlertModifier: ViewModifier {
    @Binding var error: AnkiError?

    func body(content: Content) -> some View {
        content.alert(
            "Error",
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            ),
            presenting: error
        ) { _ in
            Button("OK", role: .cancel) { error = nil }
        } message: { err in
            Text(err.localizedDescription)
        }
    }
}

extension View {
    func ankiErrorAlert(_ error: Binding<AnkiError?>) -> some View {
        modifier(AnkiErrorAlertModifier(error: error))
    }
}
