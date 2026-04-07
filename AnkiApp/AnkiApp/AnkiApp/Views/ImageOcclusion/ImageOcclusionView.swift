import SwiftUI

struct ImageOcclusionView: View {
    @Environment(AppState.self) private var appState
    @State private var model: ImageOcclusionModel?
    @State private var dragStart: CGPoint?
    @State private var currentDragRect: CGRect?

    var body: some View {
        Group {
            if let model {
                contentView(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            model = ImageOcclusionModel(service: appState.service)
        }
    }

    private func contentView(model: ImageOcclusionModel) -> some View {
        VStack(spacing: 0) {
            toolbar(model: model)
            Divider()

            if let image = model.image {
                HSplitView {
                    canvasView(model: model, image: image)
                        .frame(minWidth: 400)
                    sidePanel(model: model)
                        .frame(width: 260)
                }
            } else {
                emptyState(model: model)
            }
        }
        .navigationTitle("Image Occlusion")
    }

    private func toolbar(model: ImageOcclusionModel) -> some View {
        HStack {
            Button("Open Image") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif]
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    Task { await model.loadImage(path: url.path) }
                }
            }

            if model.image != nil {
                Divider().frame(height: 20)
                Text("\(model.rectangles.count) rectangle(s)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") {
                    model.rectangles.removeAll()
                }
                .disabled(model.rectangles.isEmpty)
                Button("Save Note") {
                    if let image = model.image {
                        Task { await model.saveNote(imageSize: image.size) }
                    }
                }
                .disabled(model.rectangles.isEmpty)
                .buttonStyle(.borderedProminent)
            } else {
                Spacer()
            }
        }
        .padding(8)
    }

    private func canvasView(model: ImageOcclusionModel, image: NSImage) -> some View {
        GeometryReader { geo in
            let imageSize = image.size
            let scale = min(geo.size.width / imageSize.width, geo.size.height / imageSize.height, 1.0)
            let scaledWidth = imageSize.width * scale
            let scaledHeight = imageSize.height * scale
            let offsetX = (geo.size.width - scaledWidth) / 2
            let offsetY = (geo.size.height - scaledHeight) / 2

            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: scaledWidth, height: scaledHeight)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                Canvas { context, _ in
                    for rect in model.rectangles {
                        let scaled = CGRect(
                            x: rect.originX * scale + offsetX,
                            y: rect.originY * scale + offsetY,
                            width: rect.width * scale,
                            height: rect.height * scale
                        )
                        context.fill(Path(scaled), with: .color(.blue.opacity(0.35)))
                        context.stroke(Path(scaled), with: .color(.blue), lineWidth: 2)
                    }
                    if let dragRect = currentDragRect {
                        context.fill(Path(dragRect), with: .color(.orange.opacity(0.3)))
                        context.stroke(Path(dragRect), with: .color(.orange), lineWidth: 2)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            if dragStart == nil {
                                dragStart = value.startLocation
                            }
                            if let start = dragStart {
                                let minX = min(start.x, value.location.x)
                                let minY = min(start.y, value.location.y)
                                let dragWidth = abs(value.location.x - start.x)
                                let dragHeight = abs(value.location.y - start.y)
                                currentDragRect = CGRect(x: minX, y: minY, width: dragWidth, height: dragHeight)
                            }
                        }
                        .onEnded { _ in
                            if let dragRect = currentDragRect {
                                let rect = OcclusionRect(
                                    originX: (dragRect.origin.x - offsetX) / scale,
                                    originY: (dragRect.origin.y - offsetY) / scale,
                                    width: dragRect.width / scale,
                                    height: dragRect.height / scale
                                )
                                if rect.width > 5, rect.height > 5 {
                                    model.addRectangle(rect)
                                }
                            }
                            dragStart = nil
                            currentDragRect = nil
                        }
                )
            }
        }
    }

    private func sidePanel(model: ImageOcclusionModel) -> some View {
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
                set: { model.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            ))
            .textFieldStyle(.roundedBorder)

            Divider()

            Text("Rectangles")
                .font(.headline)

            if model.rectangles.isEmpty {
                Text("Draw rectangles on the image to create occlusion areas.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                List {
                    ForEach(model.rectangles) { rect in
                        HStack {
                            Image(systemName: "rectangle")
                            Text("\(Int(rect.width)) x \(Int(rect.height))")
                                .font(.caption)
                            Spacer()
                            Button(role: .destructive) {
                                model.removeRectangle(id: rect.id)
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

    private func emptyState(model: ImageOcclusionModel) -> some View {
        ContentUnavailableView {
            Label("No Image", systemImage: "photo")
        } description: {
            Text("Open an image to start creating occlusion cards.")
        } actions: {
            Button("Open Image") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif]
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    Task { await model.loadImage(path: url.path) }
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ImageOcclusionView()
        .environment(AppState())
}
