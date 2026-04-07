import SwiftUI

struct CardPreviewPane: View {
    let model: CardPreviewModel
    let mediaFolderURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.showingAnswer ? "Answer" : "Question")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }
                Button(model.showingAnswer ? "Show Question" : "Show Answer") {
                    model.flipSide()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(model.selectedCardId == nil || model.isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.windowBackgroundColor))

            Divider()

            if model.selectedCardId == nil {
                ContentUnavailableView(
                    "No Card Selected",
                    systemImage: "rectangle.on.rectangle",
                    description: Text("Select a card to preview it here.")
                )
            } else if model.isLoading {
                ProgressView("Loading preview...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CardWebView(
                    html: model.showingAnswer ? model.answerHTML : model.questionHTML,
                    css: model.css,
                    baseURL: mediaFolderURL
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
