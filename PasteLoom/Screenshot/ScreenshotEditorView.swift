import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

enum ScreenshotTool: String, CaseIterable, Identifiable {
    case crop, rectangle, ellipse, arrow, line, pen, text, mosaic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .crop: "裁剪"
        case .rectangle: "矩形"
        case .ellipse: "椭圆"
        case .arrow: "箭头"
        case .line: "直线"
        case .pen: "画笔"
        case .text: "文字"
        case .mosaic: "马赛克"
        }
    }
    var symbol: String {
        switch self {
        case .crop: "crop.rotate"
        case .rectangle: "rectangle"
        case .ellipse: "oval"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .pen: "pencil.tip"
        case .text: "textformat"
        case .mosaic: "square.grid.3x3.fill"
        }
    }
}

struct ScreenshotMark: Equatable {
    let tool: ScreenshotTool
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint]
    var text: String
    var colorIndex: Int
    var lineWidth: CGFloat
}

private struct ScreenshotEditState {
    let marks: [ScreenshotMark]
    let crop: CGRect?
}

struct ScreenshotEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let document: ScreenshotDocument
    var onClose: (() -> Void)? = nil
    private let sourceImage: NSImage?
    private let pixelSize: CGSize
    @State private var tool: ScreenshotTool = .rectangle
    @State private var marks: [ScreenshotMark] = []
    @State private var history: [ScreenshotEditState] = []
    @State private var undone: [ScreenshotEditState] = []
    @State private var draft: ScreenshotMark?
    @State private var crop: CGRect?
    @State private var colorIndex = 0
    @State private var lineWidth: CGFloat = 3
    @State private var textInput = "文字"
    @State private var message: String?
    @State private var cachedPixelated: NSImage?
    @State private var ocrResult: String?
    @State private var isPerformingOCR = false

    private let swatches: [Color] = [
        Color(red: 0.27, green: 0.58, blue: 0.49),
        Color(red: 0.83, green: 0.35, blue: 0.29),
        Color(red: 0.94, green: 0.61, blue: 0.22),
        Color(red: 0.72, green: 0.40, blue: 0.58),
        Color(red: 0.35, green: 0.57, blue: 0.74),
        Color(red: 0.18, green: 0.19, blue: 0.22),
        Color(red: 0.97, green: 0.95, blue: 0.88)
    ]

    init(document: ScreenshotDocument, onClose: (() -> Void)? = nil) {
        self.document = document
        self.onClose = onClose
        sourceImage = NSImage(data: document.pngData)
        if let rep = NSBitmapImageRep(data: document.pngData) {
            pixelSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        } else {
            pixelSize = CGSize(width: 1, height: 1)
        }
    }

    private func closeEditor() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 10) {
                Spacer().frame(width: 58)
                Text("PasteLoom · 截图标注").font(.headline)
                Text("\(Int(pixelSize.width)) × \(Int(pixelSize.height))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())

                Spacer()

                Button { runOCR() } label: {
                    Label(isPerformingOCR ? "识别中…" : "识字 (OCR)", systemImage: "text.viewfinder")
                }
                .disabled(isPerformingOCR)

                Capsule().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 14)

                Button("撤销", systemImage: "arrow.uturn.backward") { undo() }
                    .disabled(history.isEmpty)
                Button("重做", systemImage: "arrow.uturn.forward") { redo() }
                    .disabled(undone.isEmpty)

                Capsule().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 14)

                Button("取消") { closeEditor() }
                Button("保存…", systemImage: "square.and.arrow.down") { save() }
                Button("复制图片", systemImage: "checkmark") { copy() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Tool & Property Capsule Bar
            HStack(spacing: 12) {
                // Drawing tools group
                HStack(spacing: 3) {
                    ForEach(ScreenshotTool.allCases) { option in
                        Button {
                            tool = option
                        } label: {
                            Image(systemName: option.symbol)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(tool == option ? Color.white : Color.primary)
                                .frame(width: 28, height: 26)
                                .background(
                                    tool == option ? Color.accentColor : Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                    }
                }
                .padding(3)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                Capsule().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 16)

                // Swatches
                HStack(spacing: 6) {
                    ForEach(Array(swatches.enumerated()), id: \.offset) { index, swatch in
                        Button { colorIndex = index } label: {
                            Circle().fill(swatch).frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: colorIndex == index ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("标注颜色 \(index + 1)")
                    }
                }

                Capsule().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 16)

                // Line width
                Picker("线宽", selection: $lineWidth) {
                    Text("细 (2pt)").tag(CGFloat(2))
                    Text("中 (3pt)").tag(CGFloat(3))
                    Text("粗 (6pt)").tag(CGFloat(6))
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                if tool == .text {
                    TextField("标注文字", text: $textInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            GeometryReader { containerGeo in
                if let image = sourceImage {
                    let paddingH: CGFloat = 32
                    let paddingV: CGFloat = 32
                    let availW = max(50, containerGeo.size.width - paddingH)
                    let availH = max(50, containerGeo.size.height - paddingV)
                    let imgRatio = max(0.01, pixelSize.width) / max(0.01, pixelSize.height)
                    let containerRatio = availW / availH
                    let fittedSize: CGSize = {
                        if imgRatio > containerRatio {
                            return CGSize(width: availW, height: availW / imgRatio)
                        } else {
                            return CGSize(width: availH * imgRatio, height: availH)
                        }
                    }()

                    ZStack {
                        ScreenshotCanvas(image: image, pixelated: cachedPixelated,
                                         marks: marks + (draft.map { [$0] } ?? []),
                                         crop: crop, colors: swatches)
                            .contentShape(Rectangle())
                            .gesture(drawingGesture(in: fittedSize))
                            .frame(width: fittedSize.width, height: fittedSize.height)
                            .shadow(color: Color.black.opacity(0.25), radius: 8, y: 3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .background(Color.black.opacity(0.12))
            Text("拖动以绘制或裁剪；文字工具使用上方输入内容。保存与复制会保留原始分辨率。")
                .font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .frame(minWidth: 860, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .alert("截图标注", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
        .sheet(item: Binding(get: {
            ocrResult.map { OCRTextWrapper(text: $0) }
        }, set: { ocrResult = $0?.text })) { wrapper in
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("截图文字识别 (OCR)").font(.headline)
                    Spacer()
                    Button("复制识别文字") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(wrapper.text, forType: .string)
                        ocrResult = nil
                    }
                    .buttonStyle(.borderedProminent)
                    Button("关闭") { ocrResult = nil }
                }
                ScrollView {
                    Text(wrapper.text).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 180, maxHeight: 320)
                .padding(10)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(20)
            .frame(minWidth: 460)
        }
        .task {
            if cachedPixelated == nil, let image = sourceImage {
                cachedPixelated = pixelatedImage(from: image)
            }
        }
    }

    private func drawingGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = normalized(value.startLocation, in: size)
                let end = normalized(value.location, in: size)
                if draft == nil {
                    draft = ScreenshotMark(tool: tool, start: start, end: end, points: [start],
                                           text: textInput, colorIndex: colorIndex, lineWidth: lineWidth)
                } else {
                    draft?.end = end
                    if tool == .pen { draft?.points.append(end) }
                }
            }
            .onEnded { _ in
                guard let draft else { return }
                if draft.tool == .crop {
                    let x = min(draft.start.x, draft.end.x)
                    let y = min(draft.start.y, draft.end.y)
                    let width = abs(draft.end.x - draft.start.x)
                    let height = abs(draft.end.y - draft.start.y)
                    if width > 0.01 && height > 0.01 {
                        recordEdit()
                        crop = CGRect(x: x, y: y, width: width, height: height)
                    }
                } else if draft.tool == .text || draft.start != draft.end {
                    recordEdit()
                    marks.append(draft)
                }
                self.draft = nil
            }
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x / max(size.width, 1), 0), 1),
                y: min(max(point.y / max(size.height, 1), 0), 1))
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        undone.append(ScreenshotEditState(marks: marks, crop: crop))
        marks = previous.marks
        crop = previous.crop
    }

    private func redo() {
        guard let next = undone.popLast() else { return }
        history.append(ScreenshotEditState(marks: marks, crop: crop))
        marks = next.marks
        crop = next.crop
    }

    private func recordEdit() {
        history.append(ScreenshotEditState(marks: marks, crop: crop))
        undone.removeAll()
    }

    @MainActor private func renderedPNG() -> Data? {
        ScreenshotAnnotationRenderer.renderPNG(source: document.pngData, marks: marks,
                                               crop: crop, colors: swatches,
                                               pixelated: cachedPixelated)
    }

    private func copy() {
        guard let data = renderedPNG(), let image = NSImage(data: data) else {
            message = "无法生成标注后的图片。"
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([image]) else { message = "写入剪贴板失败。"; return }
        closeEditor()
    }

    private func save() {
        guard let data = renderedPNG() else { message = "无法生成标注后的图片。"; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "PasteLoom Screenshot.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic); closeEditor() }
        catch { message = "保存失败：\(error.localizedDescription)" }
    }

    private func runOCR() {
        guard let data = renderedPNG() ?? document.pngData as Data? else { return }
        isPerformingOCR = true
        Task {
            defer { isPerformingOCR = false }
            do {
                let text = try await VisionOCRService.shared.recognizeText(from: data)
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    message = "截图中未识别到有效文字。"
                } else {
                    ocrResult = text
                }
            } catch {
                message = "文字识别失败：\(error.localizedDescription)"
            }
        }
    }

    private func pixelatedImage(from image: NSImage) -> NSImage? {
        ScreenshotAnnotationRenderer.pixelatedImage(from: image, pixelSize: pixelSize)
    }
}

private struct OCRTextWrapper: Identifiable {
    let id = UUID()
    let text: String
}

@MainActor
enum ScreenshotAnnotationRenderer {
    static func renderPNG(source: Data, marks: [ScreenshotMark], crop: CGRect?,
                          colors: [Color], pixelated: NSImage? = nil) -> Data? {
        guard let image = NSImage(data: source),
              let bitmapSource = NSBitmapImageRep(data: source) else { return nil }
        let size = CGSize(width: bitmapSource.pixelsWide, height: bitmapSource.pixelsHigh)
        let canvas = ScreenshotCanvas(image: image,
                                      pixelated: pixelated ?? pixelatedImage(from: image, pixelSize: size),
                                      marks: marks, crop: nil, colors: colors)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        guard let full = renderer.cgImage else { return nil }
        let cropped: CGImage
        if let crop {
            let rect = CGRect(x: crop.minX * CGFloat(full.width),
                              y: crop.minY * CGFloat(full.height),
                              width: crop.width * CGFloat(full.width),
                              height: crop.height * CGFloat(full.height)).integral
            guard let result = full.cropping(to: rect) else { return nil }
            cropped = result
        } else {
            cropped = full
        }
        let outputWidth = max(1, Int((crop?.width ?? 1) * size.width))
        let outputHeight = max(1, Int((crop?.height ?? 1) * size.height))
        guard let context = CGContext(data: nil, width: outputWidth, height: outputHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        guard let output = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])
    }

    static func pixelatedImage(from image: NSImage, pixelSize: CGSize) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              let input = CIImage(data: tiff) else { return nil }
        let filter = CIFilter.pixellate()
        filter.inputImage = input
        filter.scale = 18
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: input.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: pixelSize)
    }
}

private struct ScreenshotCanvas: View {
    let image: NSImage
    let pixelated: NSImage?
    let marks: [ScreenshotMark]
    let crop: CGRect?
    let colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            Image(nsImage: image).resizable().interpolation(.none)
                .frame(width: geometry.size.width, height: geometry.size.height)
            Canvas { context, size in
                for mark in marks {
                    let start = CGPoint(x: mark.start.x * size.width, y: mark.start.y * size.height)
                    let end = CGPoint(x: mark.end.x * size.width, y: mark.end.y * size.height)
                    let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                      width: abs(end.x - start.x), height: abs(end.y - start.y))
                    let color = colors[mark.colorIndex % colors.count]
                    let stroke = StrokeStyle(lineWidth: mark.lineWidth, lineCap: .round,
                                             lineJoin: .round)
                    switch mark.tool {
                    case .crop: break
                    case .rectangle:
                        context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(color), style: stroke)
                    case .ellipse:
                        context.stroke(Path(ellipseIn: rect), with: .color(color), style: stroke)
                    case .line, .arrow:
                        var path = Path()
                        path.move(to: start)
                        path.addLine(to: end)
                        if mark.tool == .arrow {
                            let angle = atan2(end.y - start.y, end.x - start.x)
                            let length = max(12, mark.lineWidth * 5)
                            for delta in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                                path.move(to: end)
                                path.addLine(to: CGPoint(x: end.x - length * cos(angle + delta),
                                                         y: end.y - length * sin(angle + delta)))
                            }
                        }
                        context.stroke(path, with: .color(color), style: stroke)
                    case .pen:
                        var path = Path()
                        if let first = mark.points.first {
                            path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                            for point in mark.points.dropFirst() {
                                path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                            }
                        }
                        context.stroke(path, with: .color(color), style: stroke)
                    case .text:
                        context.draw(Text(mark.text).font(.system(size: max(17, size.width / 55)))
                            .foregroundColor(color), at: start, anchor: .topLeading)
                    case .mosaic:
                        if let pixelated {
                            var clipped = context
                            clipped.clip(to: Path(rect))
                            clipped.draw(Image(nsImage: pixelated), in: CGRect(origin: .zero, size: size))
                        }
                    }
                }
                if let crop {
                    let rect = CGRect(x: crop.minX * size.width, y: crop.minY * size.height,
                                      width: crop.width * size.width, height: crop.height * size.height)
                    context.stroke(Path(rect), with: .color(.white),
                                   style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                }
            }
        }
    }
}

@MainActor
final class ScreenshotEditorWindowController: NSObject, NSWindowDelegate {
    static let shared = ScreenshotEditorWindowController()
    private var window: ScreenshotEditorWindow?

    func show(document: ScreenshotDocument) {
        if let existing = window {
            existing.orderOut(nil)
            existing.close()
            window = nil
        }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        // Center window sizing
        let targetWidth = min(1120, max(920, visible.width * 0.82))
        let targetHeight = min(800, max(680, visible.height * 0.82))
        let originX = visible.midX - targetWidth / 2
        let originY = visible.midY - targetHeight / 2
        let frameRect = NSRect(x: originX, y: originY, width: targetWidth, height: targetHeight)

        let newWindow = ScreenshotEditorWindow(
            contentRect: frameRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "PasteLoom · 截图标注"
        newWindow.titleVisibility = .hidden
        newWindow.titlebarAppearsTransparent = true
        newWindow.isMovableByWindowBackground = false
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.delegate = self
        newWindow.minSize = NSSize(width: 860, height: 600)

        let editorView = ScreenshotEditorView(document: document, onClose: { [weak self] in
            self?.close()
        })
        newWindow.contentView = NSHostingView(rootView: editorView)

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
        window?.contentView = nil
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        let win = window
        window = nil
        win?.delegate = nil
        win?.contentView = nil
    }
}

final class ScreenshotEditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { // ESC
            self.close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
