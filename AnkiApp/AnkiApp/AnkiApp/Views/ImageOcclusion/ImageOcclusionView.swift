import AppleBridgeCore
import AppleSharedUI
import SwiftUI
import UniformTypeIdentifiers

struct ImageOcclusionView: View {
    @Environment(AppState.self) private var appState
    @State private var model: ImageOcclusionModel?
    @State private var dragStart: CGPoint?
    @State private var currentDragRect: CGRect?
    @State private var showingImagePicker = false

    var editNoteId: Int64?

    var body: some View {
        Group {
            if let model {
                contentView(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            let newModel = ImageOcclusionModel(service: appState.service)
            model = newModel
            if let noteId = editNoteId {
                await newModel.loadExistingNote(noteId: noteId)
            }
        }
        .fileImporter(
            isPresented: $showingImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard let model,
                  case let .success(urls) = result,
                  let url = urls.first else {
                return
            }
            Task { await model.loadImage(path: url.path) }
        }
    }

    private func contentView(model: ImageOcclusionModel) -> some View {
        VStack(spacing: 0) {
            toolbar(model: model)
            Divider()

            if let image = model.image {
                #if os(macOS)
                    HSplitView {
                        canvasView(model: model, image: image)
                            .frame(minWidth: 400)
                        IOSidePanel(model: model)
                            .frame(width: 260)
                    }
                #else
                    VStack(spacing: 0) {
                        canvasView(model: model, image: image)
                            .frame(minHeight: 320)
                        Divider()
                        IOSidePanel(model: model)
                    }
                #endif
            } else {
                IOEmptyState(openImagePicker: {
                    showingImagePicker = true
                })
            }
        }
        .navigationTitle("Image Occlusion")
    }

    private func toolbar(model: ImageOcclusionModel) -> some View {
        HStack {
            Button("Open Image") {
                showingImagePicker = true
            }

            if model.image != nil {
                Divider().frame(height: 20)

                Picker("Shape", selection: Binding(
                    get: { model.selectedTool },
                    set: { model.selectedTool = $0 }
                )) {
                    ForEach(ShapeKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue.capitalized).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Divider().frame(height: 20)

                Text("\(model.shapes.count) shape(s)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Undo") {
                    if let last = model.shapes.last {
                        model.removeShape(id: last.id)
                    }
                }
                .disabled(model.shapes.isEmpty)
                Button("Clear All") {
                    model.shapes.removeAll()
                }
                .disabled(model.shapes.isEmpty)
                Button(model.editingNoteId != nil ? "Update Note" : "Save Note") {
                    Task { await model.saveNote() }
                }
                .disabled(model.shapes.isEmpty)
                .buttonStyle(.borderedProminent)
            } else {
                Spacer()
            }
        }
        .padding(8)
    }

    // swiftlint:disable:next function_body_length
    private func canvasView(model: ImageOcclusionModel, image: PlatformImage) -> some View {
        GeometryReader { geo in
            let imageSize = image.size
            let scale = min(
                geo.size.width / imageSize.width,
                geo.size.height / imageSize.height, 1.0
            )
            let scaledWidth = imageSize.width * scale
            let scaledHeight = imageSize.height * scale
            let offsetX = (geo.size.width - scaledWidth) / 2
            let offsetY = (geo.size.height - scaledHeight) / 2

            ZStack(alignment: .topLeading) {
                PlatformImageView(image: image)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: scaledWidth, height: scaledHeight)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                Canvas { context, _ in
                    let displaySize = CGSize(width: scaledWidth, height: scaledHeight)
                    for shape in model.shapes {
                        let rect = shape.scaled(to: displaySize)
                        let offset = CGRect(
                            x: rect.origin.x + offsetX,
                            y: rect.origin.y + offsetY,
                            width: rect.width, height: rect.height
                        )
                        drawShape(context: &context, shape: shape, rect: offset)
                    }
                    if let dragRect = currentDragRect {
                        drawDragPreview(
                            context: &context,
                            rect: dragRect, tool: model.selectedTool
                        )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            if dragStart == nil { dragStart = value.startLocation }
                            if let start = dragStart {
                                let minX = min(start.x, value.location.x)
                                let minY = min(start.y, value.location.y)
                                let dragWidth = abs(value.location.x - start.x)
                                let dragHeight = abs(value.location.y - start.y)
                                currentDragRect = CGRect(
                                    x: minX, y: minY, width: dragWidth, height: dragHeight
                                )
                            }
                        }
                        .onEnded { _ in
                            if let dragRect = currentDragRect {
                                let left = (dragRect.origin.x - offsetX) / scaledWidth
                                let top = (dragRect.origin.y - offsetY) / scaledHeight
                                let width = dragRect.width / scaledWidth
                                let height = dragRect.height / scaledHeight
                                if width > 0.01, height > 0.01 {
                                    let shape = OcclusionShape(
                                        kind: model.selectedTool,
                                        left: left, top: top,
                                        width: width, height: height,
                                        ordinal: model.nextOrdinal()
                                    )
                                    model.addShape(shape)
                                }
                            }
                            dragStart = nil
                            currentDragRect = nil
                        }
                )
            }
        }
    }

    private func drawShape(
        context: inout GraphicsContext,
        shape: OcclusionShape, rect: CGRect
    ) {
        let path = switch shape.kind {
            case .rect:
                Path(rect)
            case .ellipse:
                Path(ellipseIn: rect)
        }
        context.fill(path, with: .color(.blue.opacity(0.35)))
        context.stroke(path, with: .color(.blue), lineWidth: 2)

        // Draw ordinal label
        context.draw(
            Text("c\(shape.ordinal)").font(.caption2).foregroundStyle(.white),
            at: CGPoint(x: rect.midX, y: rect.midY)
        )
    }

    private func drawDragPreview(
        context: inout GraphicsContext,
        rect: CGRect, tool: ShapeKind
    ) {
        let path = switch tool {
            case .rect:
                Path(rect)
            case .ellipse:
                Path(ellipseIn: rect)
        }
        context.fill(path, with: .color(.orange.opacity(0.3)))
        context.stroke(path, with: .color(.orange), lineWidth: 2)
    }
}

// MARK: - Side Panel

private struct IOSidePanel: View {
    let model: ImageOcclusionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Note Fields")
                .font(.headline)

            TextField("Header", text: Binding(
                get: { model.header },
                set: { model.header = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            TextField("Back Extra", text: Binding(
                get: { model.backExtra },
                set: { model.backExtra = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            TextField("Tags (comma separated)", text: Binding(
                get: { model.tags.joined(separator: ", ") },
                set: {
                    model.tags = $0.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                }
            ))
            .textFieldStyle(.roundedBorder)

            Divider()

            Text("Shapes")
                .font(.headline)

            if model.shapes.isEmpty {
                Text("Draw shapes on the image to create occlusion areas.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                List {
                    ForEach(model.shapes) { shape in
                        HStack {
                            Image(systemName: shape.kind == .ellipse
                                ? "oval" : "rectangle")
                            Text("c\(shape.ordinal)")
                                .font(.caption).bold()
                            Spacer()
                            Button(role: .destructive) {
                                model.removeShape(id: shape.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.inset)
            }

            Spacer()

            if model.isSaved {
                Label("Note saved successfully", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            if let error = model.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding()
    }
}

// MARK: - Empty State

private struct IOEmptyState: View {
    let openImagePicker: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Image", systemImage: "photo")
        } description: {
            Text("Open an image to start creating occlusion cards.")
        } actions: {
            Button("Open Image") {
                openImagePicker()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ImageOcclusionView()
        .environment(AppState())
}
