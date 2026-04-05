import SwiftUI

struct FieldEditorView: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FieldEditorView(label: "Front", text: .constant("Hello world"))
        .padding()
}
