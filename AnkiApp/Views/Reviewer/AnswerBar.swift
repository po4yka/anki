import SwiftUI

struct AnswerBar: View {
    let model: ReviewerModel

    var body: some View {
        HStack(spacing: 12) {
            AnswerButton(label: "Again", color: .red, shortcut: "1") {
                Task { await model.answer(rating: .again) }
            }
            AnswerButton(label: "Hard", color: .orange, shortcut: "2") {
                Task { await model.answer(rating: .hard) }
            }
            AnswerButton(label: "Good", color: .green, shortcut: "3") {
                Task { await model.answer(rating: .good) }
            }
            AnswerButton(label: "Easy", color: .blue, shortcut: "4") {
                Task { await model.answer(rating: .easy) }
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
        .keyboardShortcut(KeyEquivalent(shortcut.first!), modifiers: [])
        .buttonStyle(.borderedProminent)
        .tint(color)
    }
}
