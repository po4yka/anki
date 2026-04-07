import SwiftUI

struct AnswerBar: View {
    let onAnswer: (Anki_Scheduler_CardAnswer.Rating) -> Void

    var body: some View {
        HStack(spacing: 12) {
            AnswerButton(label: "Again", color: .red, shortcut: "1") {
                onAnswer(.again)
            }
            AnswerButton(label: "Hard", color: .orange, shortcut: "2") {
                onAnswer(.hard)
            }
            AnswerButton(label: "Good", color: .green, shortcut: "3") {
                onAnswer(.good)
            }
            AnswerButton(label: "Easy", color: .blue, shortcut: "4") {
                onAnswer(.easy)
            }
        }
    }
}

private struct AnswerButton: View {
    let label: String
    let color: Color
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .frame(minWidth: 80)
        }
        // swiftlint:disable:next force_unwrapping
        .keyboardShortcut(KeyEquivalent(shortcut.first!), modifiers: [])
        .buttonStyle(.borderedProminent)
        .tint(color)
    }
}
