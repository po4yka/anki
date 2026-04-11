import AppleBridgeCore
import AppleSharedUI
import SwiftUI

struct DeckPicker: View {
    let model: NoteEditorModel

    var body: some View {
        @Bindable var model = model
        Picker("Deck", selection: $model.selectedDeckId) {
            ForEach(model.availableDecks, id: \.id) { deck in
                Text(deck.name).tag(deck.id as Int64?)
            }
        }
    }
}
