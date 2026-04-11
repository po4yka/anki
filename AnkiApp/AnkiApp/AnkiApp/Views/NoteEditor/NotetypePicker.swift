import SwiftUI
import AppleBridgeCore
import AppleSharedUI

struct NotetypePicker: View {
    let model: NoteEditorModel

    var body: some View {
        @Bindable var model = model
        Picker("Note Type", selection: $model.selectedNotetypeId) {
            ForEach(model.availableNotetypes, id: \.id) { notetype in
                Text(notetype.name).tag(notetype.id as Int64?)
            }
        }
        .onChange(of: model.selectedNotetypeId) { _, _ in
            Task { await model.loadNotetype() }
        }
    }
}
