import Foundation
import Observation
import AppleBridgeCore
import AppleSharedUI

@Observable
@MainActor
final class NotetypeModel {
    var notetypes: [Anki_Notetypes_NotetypeNameIdUseCount] = []
    var selectedNotetype: Anki_Notetypes_Notetype?
    var isLoading: Bool = false
    var error: AnkiError?

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await service.getNotetypeNamesAndCounts()
            notetypes = response.entries
            error = nil
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func selectNotetype(id: Int64) async {
        do {
            selectedNotetype = try await service.getNotetype(id: id)
            error = nil
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func addNotetype(name: String, kind: Anki_Notetypes_Notetype.Config.Kind = .normal) async {
        do {
            var notetype = Anki_Notetypes_Notetype()
            notetype.name = name
            var config = Anki_Notetypes_Notetype.Config()
            config.kind = kind
            notetype.config = config

            var field = Anki_Notetypes_Notetype.Field()
            field.name = "Front"
            var fieldOrd = Anki_Generic_UInt32()
            fieldOrd.val = 0
            field.ord = fieldOrd
            notetype.fields.append(field)

            var backField = Anki_Notetypes_Notetype.Field()
            backField.name = "Back"
            var backOrd = Anki_Generic_UInt32()
            backOrd.val = 1
            backField.ord = backOrd
            notetype.fields.append(backField)

            var template = Anki_Notetypes_Notetype.Template()
            template.name = "Card 1"
            var tmplOrd = Anki_Generic_UInt32()
            tmplOrd.val = 0
            template.ord = tmplOrd
            var tmplConfig = Anki_Notetypes_Notetype.Template.Config()
            tmplConfig.qFormat = "{{Front}}"
            tmplConfig.aFormat = "{{FrontSide}}<hr id=answer>{{Back}}"
            template.config = tmplConfig
            notetype.templates.append(template)

            _ = try await service.addNotetype(notetype: notetype)
            await load()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func cloneNotetype(id: Int64, newName: String) async {
        do {
            var source = try await service.getNotetype(id: id)
            source.id = 0
            source.name = newName
            _ = try await service.addNotetype(notetype: source)
            await load()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func deleteNotetype(id: Int64) async {
        do {
            _ = try await service.removeNotetype(id: id)
            if selectedNotetype?.id == id {
                selectedNotetype = nil
            }
            await load()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func addField(name: String) async {
        guard var notetype = selectedNotetype else { return }
        var field = Anki_Notetypes_Notetype.Field()
        field.name = name
        var ord = Anki_Generic_UInt32()
        ord.val = UInt32(notetype.fields.count)
        field.ord = ord
        notetype.fields.append(field)
        await saveNotetype(notetype)
    }

    func removeField(at index: Int) async {
        guard var notetype = selectedNotetype, notetype.fields.count > 1 else { return }
        notetype.fields.remove(at: index)
        for idx in 0 ..< notetype.fields.count {
            var ord = Anki_Generic_UInt32()
            ord.val = UInt32(idx)
            notetype.fields[idx].ord = ord
        }
        await saveNotetype(notetype)
    }

    func moveField(from: Int, to destination: Int) async {
        guard var notetype = selectedNotetype else { return }
        let field = notetype.fields.remove(at: from)
        notetype.fields.insert(field, at: destination)
        for idx in 0 ..< notetype.fields.count {
            var ord = Anki_Generic_UInt32()
            ord.val = UInt32(idx)
            notetype.fields[idx].ord = ord
        }
        await saveNotetype(notetype)
    }

    func updateTemplateFront(index: Int, format: String) async {
        guard var notetype = selectedNotetype, index < notetype.templates.count else { return }
        notetype.templates[index].config.qFormat = format
        await saveNotetype(notetype)
    }

    func updateTemplateBack(index: Int, format: String) async {
        guard var notetype = selectedNotetype, index < notetype.templates.count else { return }
        notetype.templates[index].config.aFormat = format
        await saveNotetype(notetype)
    }

    func updateCSS(_ css: String) async {
        guard var notetype = selectedNotetype else { return }
        notetype.config.css = css
        await saveNotetype(notetype)
    }

    private func saveNotetype(_ notetype: Anki_Notetypes_Notetype) async {
        do {
            _ = try await service.updateNotetype(notetype: notetype)
            selectedNotetype = notetype
            await load()
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }
}
