import Foundation
import Observation
import AppKit

struct OcclusionRect: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

@Observable
@MainActor
final class ImageOcclusionModel {
    var image: NSImage? = nil
    var imagePath: String = ""
    var imageName: String = ""
    var rectangles: [OcclusionRect] = []
    var header: String = ""
    var backExtra: String = ""
    var tags: [String] = []
    var notetypeId: Int64 = 0
    var isLoading: Bool = false
    var error: AnkiError? = nil
    var isSaved: Bool = false

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
            rectangles = []
            isSaved = false
            error = nil
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func addRectangle(_ rect: OcclusionRect) {
        rectangles.append(rect)
    }

    func removeRectangle(id: UUID) {
        rectangles.removeAll { $0.id == id }
    }

    func updateRectangle(id: UUID, rect: OcclusionRect) {
        if let index = rectangles.firstIndex(where: { $0.id == id }) {
            rectangles[index] = rect
        }
    }

    func generateOcclusionsJSON(imageSize: CGSize) -> String {
        guard !rectangles.isEmpty, imageSize.width > 0, imageSize.height > 0 else { return "[]" }
        var shapes: [[String: Any]] = []
        for rect in rectangles {
            let normalized: [String: Any] = [
                "left": rect.x / imageSize.width,
                "top": rect.y / imageSize.height,
                "width": rect.width / imageSize.width,
                "height": rect.height / imageSize.height
            ]
            shapes.append(normalized)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: shapes),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    func saveNote(imageSize: CGSize) async {
        guard !rectangles.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var req = Anki_ImageOcclusion_AddImageOcclusionNoteRequest()
            req.imagePath = imagePath
            req.occlusions = generateOcclusionsJSON(imageSize: imageSize)
            req.header = header
            req.backExtra = backExtra
            req.tags = tags
            req.notetypeID = notetypeId
            _ = try await service.addImageOcclusionNote(request: req)
            isSaved = true
            error = nil
        } catch let e as AnkiError {
            error = e
        } catch {}
    }

    func reset() {
        image = nil
        imagePath = ""
        imageName = ""
        rectangles = []
        header = ""
        backExtra = ""
        tags = []
        isSaved = false
        error = nil
    }
}
