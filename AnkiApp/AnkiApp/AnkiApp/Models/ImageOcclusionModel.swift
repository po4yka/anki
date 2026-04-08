import AppKit
import Foundation
import Observation

enum ShapeKind: String, CaseIterable {
    case rect
    case ellipse
}

struct OcclusionShape: Identifiable {
    let id = UUID()
    var kind: ShapeKind
    // Normalized coordinates (0.0-1.0 fractions of image size)
    var left: CGFloat
    var top: CGFloat
    var width: CGFloat
    var height: CGFloat
    var ordinal: Int

    var cgRect: CGRect {
        CGRect(x: left, y: top, width: width, height: height)
    }

    func scaled(to size: CGSize) -> CGRect {
        CGRect(
            x: left * size.width,
            y: top * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}

@Observable
@MainActor
final class ImageOcclusionModel {
    var image: NSImage?
    var imagePath: String = ""
    var imageName: String = ""
    var shapes: [OcclusionShape] = []
    var header: String = ""
    var backExtra: String = ""
    var tags: [String] = []
    var notetypeId: Int64 = 0
    var isLoading: Bool = false
    var error: AnkiError?
    var isSaved: Bool = false
    var selectedTool: ShapeKind = .rect
    var editingNoteId: Int64?

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    func loadImage(path: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await service.getImageForOcclusion(path: path)
            imagePath = path
            imageName = response.name
            image = NSImage(data: response.data)
            shapes = []
            isSaved = false
            editingNoteId = nil
            error = nil
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func loadExistingNote(noteId: Int64) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await service.getImageOcclusionNote(noteId: noteId)
            guard case let .note(note) = response.value else {
                if case let .error(msg) = response.value {
                    error = AnkiError(localized: msg)
                }
                return
            }
            editingNoteId = noteId
            image = NSImage(data: note.imageData)
            imageName = note.imageFileName
            header = note.header
            backExtra = note.backExtra
            tags = note.tags
            shapes = note.occlusions.flatMap { parseOcclusion($0) }
            isSaved = false
            error = nil
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    private func parseOcclusion(
        _ occlusion: Anki_ImageOcclusion_GetImageOcclusionNoteResponse.ImageOcclusion
    ) -> [OcclusionShape] {
        occlusion.shapes.map { shape in
            let kind = ShapeKind(rawValue: shape.shape) ?? .rect
            let props = Dictionary(
                shape.properties.map { ($0.name, CGFloat(Double($0.value) ?? 0)) },
                uniquingKeysWith: { _, last in last }
            )
            return OcclusionShape(
                kind: kind,
                left: props["left"] ?? 0, top: props["top"] ?? 0,
                width: props["width"] ?? 0, height: props["height"] ?? 0,
                ordinal: Int(occlusion.ordinal)
            )
        }
    }

    func addShape(_ shape: OcclusionShape) {
        shapes.append(shape)
    }

    func removeShape(id: UUID) {
        shapes.removeAll { $0.id == id }
    }

    func nextOrdinal() -> Int {
        (shapes.map(\.ordinal).max() ?? 0) + 1
    }

    func generateOcclusionsText() -> String {
        shapes.map { shape in
            let leftStr = String(format: "%.4f", shape.left)
            let topStr = String(format: "%.4f", shape.top)
            let widthStr = String(format: "%.4f", shape.width)
            let heightStr = String(format: "%.4f", shape.height)
            return "{{c\(shape.ordinal)::image-occlusion:\(shape.kind.rawValue)" +
                ":left=\(leftStr):top=\(topStr):width=\(widthStr):height=\(heightStr)}}"
        }.joined()
    }

    func saveNote() async {
        guard !shapes.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if let noteId = editingNoteId {
                var req = Anki_ImageOcclusion_UpdateImageOcclusionNoteRequest()
                req.noteID = noteId
                req.occlusions = generateOcclusionsText()
                req.header = header
                req.backExtra = backExtra
                req.tags = tags
                _ = try await service.updateImageOcclusionNote(request: req)
            } else {
                var req = Anki_ImageOcclusion_AddImageOcclusionNoteRequest()
                req.imagePath = imagePath
                req.occlusions = generateOcclusionsText()
                req.header = header
                req.backExtra = backExtra
                req.tags = tags
                req.notetypeID = notetypeId
                _ = try await service.addImageOcclusionNote(request: req)
            }
            isSaved = true
            error = nil
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func reset() {
        image = nil
        imagePath = ""
        imageName = ""
        shapes = []
        header = ""
        backExtra = ""
        tags = []
        isSaved = false
        editingNoteId = nil
        error = nil
    }
}
