import SwiftUI
import AppleBridgeCore
import AppleSharedUI

struct AnswerBar: View {
    struct Choice: Identifiable {
        let rating: Anki_Scheduler_CardAnswer.Rating
        let label: String
        let interval: String?
        let color: Color
        let shortcut: String

        var id: Int {
            rating.rawValue
        }
    }

    let choices: [Choice]
    let onAnswer: (Anki_Scheduler_CardAnswer.Rating) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(choices) { choice in
                AnswerButton(
                    label: choice.label,
                    interval: choice.interval,
                    color: choice.color,
                    shortcut: choice.shortcut
                ) {
                    onAnswer(choice.rating)
                }
            }
        }
    }
}

private struct AnswerButton: View {
    let label: String
    let interval: String?
    let color: Color
    let shortcut: String
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                if let interval {
                    Text(interval)
                        .font(.caption2)
                        .foregroundStyle(.primary.opacity(0.85))
                }
            }
            .frame(minWidth: 80)
        }

        if let key = shortcut.first {
            button
                .keyboardShortcut(KeyEquivalent(key), modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(color)
        } else {
            button
                .buttonStyle(.borderedProminent)
                .tint(color)
        }
    }
}
