import AppKit
import ScreenCaptureKit
import SwiftUI

enum InteractiveCaptureMode {
    case annotate
    case quick
}

// MARK: - Panel Bridge for Keyboard & Mouse Actions
@MainActor
final class ScreenshotPanelBridge: ObservableObject {
    var onConfirm: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onCancel: (() -> Void)?
    var onSpacebar: (() -> Void)?
    var onMouseMoved: ((CGPoint) -> Void)?
}

// MARK: - Custom NSHostingView with Mouse Tracking Area
final class ScreenshotHostingView<Content: View>: NSHostingView<Content> {
    var onMouseMoved: ((CGPoint) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let loc = convert(event.locationInWindow, from: nil)
        let flipped = CGPoint(x: loc.x, y: bounds.height - loc.y)
        onMouseMoved?(flipped)
    }
}

// MARK: - Detected Window Candidate Model
struct DetectedWindowCandidate: Identifiable, Equatable {
    let id: CGWindowID
    let appName: String
    let windowTitle: String
    let rect: CGRect

    var displayName: String {
        if windowTitle.isEmpty || windowTitle == appName {
            return appName
        }
        return "\(appName) — \(windowTitle)"
    }

    static func detectCandidates(for screen: NSScreen, excludingWindowNumber: Int? = nil) -> [DetectedWindowCandidate] {
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenQuartzTopLeftX = screen.frame.minX
        let screenQuartzTopLeftY = primaryScreenHeight - screen.frame.maxY
        let screenLocalBounds = CGRect(origin: .zero, size: screen.frame.size)

        var candidates: [DetectedWindowCandidate] = []
        let excludedApps: Set<String> = [
            "Dock", "Window Server", "Wallpaper", "Notification Center",
            "ControlCenter", "控制中心", "SystemUIServer", "Spotlight", "Cursor"
        ]

        for info in windowInfoList {
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { continue }

            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1.0
            guard alpha > 0.4 else { continue }

            if let winNumber = info[kCGWindowNumber as String] as? Int {
                if let excluding = excludingWindowNumber, winNumber == excluding {
                    continue
                }
            }

            let ownerName = (info[kCGWindowOwnerName as String] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ownerName.isEmpty, !excludedApps.contains(ownerName) else { continue }

            let windowTitle = (info[kCGWindowName as String] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            // Exclude internal overlay windows of PasteLoom if title is empty
            if ownerName.contains("PasteLoom") && windowTitle.isEmpty {
                continue
            }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let quartzBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            let localX = quartzBounds.origin.x - screenQuartzTopLeftX
            let localY = quartzBounds.origin.y - screenQuartzTopLeftY
            let localRect = CGRect(x: localX, y: localY, width: quartzBounds.width, height: quartzBounds.height)

            let clampedRect = localRect.intersection(screenLocalBounds).integral
            guard !clampedRect.isNull, clampedRect.width >= 80, clampedRect.height >= 80 else {
                continue
            }

            let candidateId = CGWindowID(info[kCGWindowNumber as String] as? Int ?? 0)
            candidates.append(DetectedWindowCandidate(
                id: candidateId,
                appName: ownerName,
                windowTitle: windowTitle,
                rect: clampedRect
            ))
        }

        return candidates
    }
}

// MARK: - Interactive Screenshot Coordinator
@MainActor
final class InteractiveScreenshotCoordinator: ObservableObject {
    static let shared = InteractiveScreenshotCoordinator()

    private var currentPanel: InteractiveScreenshotPanel?

    func startCapture(mode: InteractiveCaptureMode,
                      onAnnotate: @escaping (ScreenshotDocument) -> Void = { _ in },
                      onQuickCopied: @escaping () -> Void = {}) {
        currentPanel?.close()
        currentPanel = nil

        Task { @MainActor in
            do {
                if !ScreenshotPermission.isGranted {
                    ScreenshotPermission.requestAccess()
                }
                let captureService = ScreenshotCaptureService()
                let (cgImage, display) = try await captureService.captureCurrentDisplayCGImage()
                let windowList = try? await captureService.fetchShareableWindows()

                let screen = NSScreen.screens.first(where: {
                    $0.frame.contains(NSEvent.mouseLocation)
                }) ?? NSScreen.main ?? NSScreen.screens[0]

                let bridge = ScreenshotPanelBridge()

                let panel = InteractiveScreenshotPanel(
                    screen: screen,
                    capturedCGImage: cgImage,
                    display: display,
                    windows: windowList ?? [],
                    mode: mode,
                    bridge: bridge,
                    onFinish: { [weak self] document, isQuick in
                        self?.currentPanel?.close()
                        self?.currentPanel = nil
                        guard let document else { return }
                        if isQuick {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            if let image = NSImage(data: document.pngData) {
                                _ = pasteboard.writeObjects([image])
                            }
                            NSSound.beep()
                            onQuickCopied()
                        } else {
                            onAnnotate(document)
                        }
                    }
                )
                self.currentPanel = panel
                panel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } catch {
                ScreenshotPermission.openSettings()
                let alert = NSAlert()
                alert.messageText = "截屏授权刷新提示"
                alert.informativeText = "macOS 屏幕录制权限尚未生效。\n\n系统设置已为您打开：请在“屏幕与系统录制”列表中，将 PasteLoom 开关关闭后重新开启一次（刷新当前构建签名绑定），即可正常截图标注。"
                alert.runModal()
            }
        }
    }
}

// MARK: - Interactive Screenshot Panel (Fullscreen Transparent NSPanel)
private final class InteractiveScreenshotPanel: NSPanel {
    private let bridge: ScreenshotPanelBridge
    private var hostingView: ScreenshotHostingView<InteractiveSelectionView>?

    init(screen: NSScreen,
         capturedCGImage: CGImage,
         display: SCDisplay?,
         windows: [SCWindow],
         mode: InteractiveCaptureMode,
         bridge: ScreenshotPanelBridge,
         onFinish: @escaping (ScreenshotDocument?, Bool) -> Void) {
        self.bridge = bridge
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        self.isExcludedFromWindowsMenu = true
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true

        let selectionView = InteractiveSelectionView(
            screen: screen,
            capturedCGImage: capturedCGImage,
            display: display,
            windows: windows,
            overlayWindowNumber: self.windowNumber,
            mode: mode,
            bridge: bridge,
            onDismiss: { onFinish(nil, false) },
            onComplete: { doc, isQuick in onFinish(doc, isQuick) }
        )
        let hosting = ScreenshotHostingView(rootView: selectionView)
        hosting.onMouseMoved = { [weak bridge] point in
            bridge?.onMouseMoved?(point)
        }
        self.hostingView = hosting
        self.contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            bridge.onCancel?() ?? close()
        } else if event.keyCode == 49 { // Space
            bridge.onSpacebar?()
        } else if event.keyCode == 36 { // Return / Enter
            bridge.onConfirm?()
        } else if event.keyCode == 6 && event.modifierFlags.contains(.command) { // Cmd+Z
            if event.modifierFlags.contains(.shift) {
                bridge.onRedo?()
            } else {
                bridge.onUndo?()
            }
        } else {
            super.keyDown(with: event)
        }
    }

    override func close() {
        self.hostingView?.onMouseMoved = nil
        self.hostingView = nil
        self.contentView = nil
        super.close()
    }
}

// MARK: - 8 Resize Handles
enum ResizeHandle: String, CaseIterable, Identifiable {
    case topLeft, topCenter, topRight
    case middleLeft, middleRight
    case bottomLeft, bottomCenter, bottomRight

    var id: String { rawValue }

    var cursor: NSCursor {
        switch self {
        case .topCenter, .bottomCenter:
            return .resizeUpDown
        case .middleLeft, .middleRight:
            return .resizeLeftRight
        case .topLeft, .bottomRight, .topRight, .bottomLeft:
            return .crosshair
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topCenter: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .middleLeft: return CGPoint(x: rect.minX, y: rect.midY)
        case .middleRight: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomCenter: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

// MARK: - Pinned Screenshot Window Controller (贴图)
@MainActor
final class PinnedScreenshotWindowController {
    static let shared = PinnedScreenshotWindowController()
    private var windows: [NSWindow] = []

    func pin(image: NSImage, at screenRect: NSRect? = nil) {
        let size = image.size
        let frame: NSRect
        if let screenRect, screenRect.width > 20, screenRect.height > 20 {
            frame = screenRect
        } else {
            let mouse = NSEvent.mouseLocation
            frame = NSRect(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2,
                           width: size.width, height: size.height)
        }

        let panel = PinnedImagePanel(image: image, contentRect: frame) { [weak self] window in
            self?.windows.removeAll(where: { $0 === window })
        }
        windows.append(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func closeAll() {
        for w in windows { w.close() }
        windows.removeAll()
    }
}

private final class PinnedImagePanel: NSPanel {
    init(image: NSImage, contentRect: NSRect, onClose: @escaping (NSPanel) -> Void) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        self.isExcludedFromWindowsMenu = true

        let hostingView = NSHostingView(
            rootView: PinnedImageView(image: image, onClose: { [weak self] in
                guard let self else { return }
                onClose(self)
                self.close()
            })
        )
        self.contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            self.close()
        } else {
            super.keyDown(with: event)
        }
    }

    override func close() {
        self.contentView = nil
        super.close()
    }
}

private struct PinnedImageView: View {
    let image: NSImage
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.75)
                )

            if isHovering {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.black.opacity(0.65), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("复制图片") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([image])
            }
            Divider()
            Button("关闭贴图") { onClose() }
        }
    }
}

// MARK: - Main Interactive Selection View
private struct InteractiveSelectionView: View {
    let screen: NSScreen
    let capturedCGImage: CGImage
    let display: SCDisplay?
    let windows: [SCWindow]
    let overlayWindowNumber: Int
    let mode: InteractiveCaptureMode
    let bridge: ScreenshotPanelBridge
    let onDismiss: () -> Void
    let onComplete: (ScreenshotDocument?, Bool) -> Void

    // Selection & Resize State
    @State private var selectedRect: CGRect?
    @State private var handleDragStartRect: CGRect?
    @State private var moveDragStartRect: CGRect?

    // Window Snap State
    @State private var windowCandidates: [DetectedWindowCandidate] = []
    @State private var hoveredWindow: DetectedWindowCandidate?
    @State private var isDraggingManualSelection: Bool = false

    // Tool & Annotation State
    @State private var currentTool: ScreenshotTool? = nil
    @State private var marks: [ScreenshotMark] = []
    @State private var history: [[ScreenshotMark]] = []
    @State private var undone: [[ScreenshotMark]] = []
    @State private var draftMark: ScreenshotMark?
    @State private var colorIndex: Int = 0
    @State private var lineWidth: CGFloat = 3.5
    @State private var textInput: String = "标注文字"
    @State private var cachedPixelated: NSImage?

    // OCR State
    @State private var ocrTextResult: String?
    @State private var isProcessingOCR = false
    @State private var showOCRSheet = false

    // Color Swatches (Apple HIG vibrant & clear)
    private let swatches: [Color] = [
        Color(red: 0.94, green: 0.27, blue: 0.22), // Red
        Color(red: 0.97, green: 0.56, blue: 0.04), // Orange
        Color(red: 0.99, green: 0.69, blue: 0.13), // Yellow
        Color(red: 0.07, green: 0.72, blue: 0.42), // Green
        Color(red: 0.04, green: 0.65, blue: 0.93), // Blue
        Color(red: 0.48, green: 0.35, blue: 0.97), // Purple
        Color.white,                                // White
        Color(red: 0.11, green: 0.16, blue: 0.22)  // Dark Slate
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed background with Drag gesture for creating new selection
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        guard selectedRect == nil, !isDraggingManualSelection else { return }
                        switch phase {
                        case .active(let location):
                            let candidate = windowCandidates.first(where: { $0.rect.contains(location) })
                            if hoveredWindow?.id != candidate?.id {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    hoveredWindow = candidate
                                }
                            }
                        case .ended:
                            if hoveredWindow != nil {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    hoveredWindow = nil
                                }
                            }
                        }
                    }
                    .gesture(backgroundDragGesture(in: geometry.size))

                // Window snap candidate highlight (visible when hovering a window prior to manual selection)
                if let target = hoveredWindow, selectedRect == nil, !isDraggingManualSelection {
                    candidateHighlightView(for: target, in: geometry.size)
                }

                // Selection cutout & content
                if let rect = selectedRect {
                    // Clear cutout so original screen underneath is crystal-clear
                    Canvas { context, size in
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.35)))
                        context.blendMode = .clear
                        context.fill(Path(rect), with: .color(.white))
                    }
                    .allowsHitTesting(false)

                    // Live Drawing Layer & Gestures inside selectedRect
                    ZStack {
                        // Render marks inside selected rect
                        marksCanvas(in: rect)

                        // Gesture layer inside rect: draws marks if tool active, else moves box
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(insideSelectionGesture(in: rect, viewSize: geometry.size))
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                    // Crisp Selection Border
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1.5)
                        .shadow(color: Color.black.opacity(0.4), radius: 1, y: 0.5)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)

                    // 8 Resize Handles
                    ForEach(ResizeHandle.allCases) { handle in
                        handleView(handle, in: rect, viewSize: geometry.size)
                    }

                    // Dimensions badge (e.g. 950 × 572)
                    dimensionBadge(for: rect, in: geometry.size)

                    // Floating HUD Capsule Toolbar (tightly attached below/above selection)
                    floatingHUD(for: rect, in: geometry.size)
                }

                // Top Pill Bar (PasteLoom · 贴图 · 全选屏 · ✕)
                topPillBar(in: geometry.size)

                // Subtitle guide hint when no selection is active and no window is hovered
                if selectedRect == nil && hoveredWindow == nil && !isDraggingManualSelection {
                    guideHintBadge(in: geometry.size)
                }
            }
            .onAppear {
                NSCursor.crosshair.push()
                windowCandidates = DetectedWindowCandidate.detectCandidates(for: screen, excludingWindowNumber: overlayWindowNumber)
                setupBridge(viewSize: geometry.size)
            }
            .onDisappear {
                NSCursor.pop()
            }
            .sheet(isPresented: $showOCRSheet) {
                ocrSheetView
            }
        }
    }

    // MARK: - Bridge Setup
    private func setupBridge(viewSize: CGSize) {
        bridge.onConfirm = {
            if let rect = selectedRect {
                confirmCapture(rect: rect, viewSize: viewSize, isQuick: true)
            }
        }
        bridge.onSpacebar = {
            if selectedRect == nil, let target = hoveredWindow {
                selectedRect = target.rect
                hoveredWindow = nil
                updatePixelatedCrop(rect: target.rect, viewSize: viewSize)
            } else if selectedRect != nil {
                selectedRect = nil
                marks.removeAll()
                undone.removeAll()
                history.removeAll()
                currentTool = nil
            }
        }
        bridge.onMouseMoved = { pt in
            guard selectedRect == nil, !isDraggingManualSelection else { return }
            let candidate = windowCandidates.first(where: { $0.rect.contains(pt) })
            if hoveredWindow?.id != candidate?.id {
                withAnimation(.easeOut(duration: 0.12)) {
                    hoveredWindow = candidate
                }
            }
        }
        bridge.onUndo = { undo() }
        bridge.onRedo = { redo() }
        bridge.onCancel = {
            if selectedRect != nil {
                selectedRect = nil
                marks.removeAll()
                undone.removeAll()
                history.removeAll()
                currentTool = nil
            } else {
                onDismiss()
            }
        }
    }

    // MARK: - Background Drag Gesture
    private func backgroundDragGesture(in viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let dx = abs(value.location.x - value.startLocation.x)
                let dy = abs(value.location.y - value.startLocation.y)

                if dx > 4 || dy > 4 {
                    if !isDraggingManualSelection {
                        isDraggingManualSelection = true
                        hoveredWindow = nil
                        if selectedRect != nil {
                            marks.removeAll()
                            undone.removeAll()
                            history.removeAll()
                            currentTool = nil
                        }
                    }
                    let start = value.startLocation
                    let end = value.location
                    selectedRect = CGRect(
                        x: min(start.x, end.x),
                        y: min(start.y, end.y),
                        width: max(abs(end.x - start.x), 2),
                        height: max(abs(end.y - start.y), 2)
                    )
                }
            }
            .onEnded { value in
                let dx = abs(value.location.x - value.startLocation.x)
                let dy = abs(value.location.y - value.startLocation.y)
                let isClick = (dx <= 4 && dy <= 4)

                if isClick {
                    if let target = hoveredWindow {
                        selectedRect = target.rect
                        hoveredWindow = nil
                        updatePixelatedCrop(rect: target.rect, viewSize: viewSize)
                    } else if selectedRect != nil {
                        selectedRect = nil
                        marks.removeAll()
                        undone.removeAll()
                        history.removeAll()
                        currentTool = nil
                    }
                } else {
                    if let rect = selectedRect, rect.width >= 10 && rect.height >= 10 {
                        updatePixelatedCrop(rect: rect, viewSize: viewSize)
                    } else {
                        selectedRect = nil
                    }
                }
                isDraggingManualSelection = false
            }
    }

    // MARK: - Inside Selection Gesture (Draw Marks OR Move Box)
    private func insideSelectionGesture(in rect: CGRect, viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if let tool = currentTool {
                    // Normalize coordinates relative to rect
                    let normStart = CGPoint(
                        x: min(max(value.startLocation.x / max(rect.width, 1), 0), 1),
                        y: min(max(value.startLocation.y / max(rect.height, 1), 0), 1)
                    )
                    let normEnd = CGPoint(
                        x: min(max(value.location.x / max(rect.width, 1), 0), 1),
                        y: min(max(value.location.y / max(rect.height, 1), 0), 1)
                    )
                    if draftMark == nil {
                        draftMark = ScreenshotMark(
                            tool: tool,
                            start: normStart,
                            end: normEnd,
                            points: [normStart],
                            text: textInput,
                            colorIndex: colorIndex,
                            lineWidth: lineWidth
                        )
                    } else {
                        draftMark?.end = normEnd
                        if tool == .pen {
                            draftMark?.points.append(normEnd)
                        }
                    }
                } else {
                    // Move selection box
                    if moveDragStartRect == nil {
                        moveDragStartRect = rect
                    }
                    guard let startRect = moveDragStartRect else { return }
                    let newX = min(max(startRect.origin.x + value.translation.width, 0), viewSize.width - startRect.width)
                    let newY = min(max(startRect.origin.y + value.translation.height, 0), viewSize.height - startRect.height)
                    selectedRect = CGRect(x: newX, y: newY, width: startRect.width, height: startRect.height)
                }
            }
            .onEnded { _ in
                if currentTool != nil {
                    if let draft = draftMark {
                        if draft.tool == .text || draft.start != draft.end || draft.points.count > 1 {
                            recordEdit()
                            marks.append(draft)
                        }
                    }
                    draftMark = nil
                } else {
                    moveDragStartRect = nil
                    if let rect = selectedRect {
                        updatePixelatedCrop(rect: rect, viewSize: viewSize)
                    }
                }
            }
    }

    // MARK: - 8 Resize Handles
    private func handleView(_ handle: ResizeHandle, in rect: CGRect, viewSize: CGSize) -> some View {
        let pt = handle.point(in: rect)
        return ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: 7, height: 7)
                .overlay(
                    Rectangle().strokeBorder(Color.black.opacity(0.4), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 1, y: 0.5)
        }
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
        .position(pt)
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .onChanged { value in
                    if handleDragStartRect == nil {
                        handleDragStartRect = rect
                    }
                    guard let startRect = handleDragStartRect else { return }
                    selectedRect = updatedRect(for: handle, original: startRect, translation: value.translation, bounds: viewSize)
                }
                .onEnded { _ in
                    handleDragStartRect = nil
                    if let rect = selectedRect {
                        updatePixelatedCrop(rect: rect, viewSize: viewSize)
                    }
                }
        )
    }

    private func updatedRect(for handle: ResizeHandle, original: CGRect, translation: CGSize, bounds: CGSize) -> CGRect {
        var minX = original.minX
        var minY = original.minY
        var maxX = original.maxX
        var maxY = original.maxY

        switch handle {
        case .topLeft:
            minX = min(original.maxX - 20, max(0, original.minX + translation.width))
            minY = min(original.maxY - 20, max(0, original.minY + translation.height))
        case .topCenter:
            minY = min(original.maxY - 20, max(0, original.minY + translation.height))
        case .topRight:
            maxX = max(original.minX + 20, min(bounds.width, original.maxX + translation.width))
            minY = min(original.maxY - 20, max(0, original.minY + translation.height))
        case .middleLeft:
            minX = min(original.maxX - 20, max(0, original.minX + translation.width))
        case .middleRight:
            maxX = max(original.minX + 20, min(bounds.width, original.maxX + translation.width))
        case .bottomLeft:
            minX = min(original.maxX - 20, max(0, original.minX + translation.width))
            maxY = max(original.minY + 20, min(bounds.height, original.maxY + translation.height))
        case .bottomCenter:
            maxY = max(original.minY + 20, min(bounds.height, original.maxY + translation.height))
        case .bottomRight:
            maxX = max(original.minX + 20, min(bounds.width, original.maxX + translation.width))
            maxY = max(original.minY + 20, min(bounds.height, original.maxY + translation.height))
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Marks Canvas
    private func marksCanvas(in rect: CGRect) -> some View {
        Canvas { context, size in
            let allMarks = marks + (draftMark.map { [$0] } ?? [])
            for mark in allMarks {
                let start = CGPoint(x: mark.start.x * size.width, y: mark.start.y * size.height)
                let end = CGPoint(x: mark.end.x * size.width, y: mark.end.y * size.height)
                let itemRect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                      width: max(abs(end.x - start.x), 1), height: max(abs(end.y - start.y), 1))
                let color = swatches[mark.colorIndex % swatches.count]
                let stroke = StrokeStyle(lineWidth: mark.lineWidth, lineCap: .round, lineJoin: .round)

                switch mark.tool {
                case .crop: break
                case .rectangle:
                    context.stroke(Path(roundedRect: itemRect, cornerRadius: 3), with: .color(color), style: stroke)
                case .ellipse:
                    context.stroke(Path(ellipseIn: itemRect), with: .color(color), style: stroke)
                case .line, .arrow:
                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)
                    if mark.tool == .arrow {
                        let angle = atan2(end.y - start.y, end.x - start.x)
                        let length = max(12, mark.lineWidth * 4.5)
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
                        for pt in mark.points.dropFirst() {
                            path.addLine(to: CGPoint(x: pt.x * size.width, y: pt.y * size.height))
                        }
                    }
                    context.stroke(path, with: .color(color), style: stroke)
                case .text:
                    context.draw(
                        Text(mark.text)
                            .font(.system(size: max(16, mark.lineWidth * 5), weight: .semibold))
                            .foregroundColor(color),
                        at: start,
                        anchor: .topLeading
                    )
                case .mosaic:
                    if let cachedPixelated {
                        var clipped = context
                        clipped.clip(to: Path(itemRect))
                        clipped.draw(Image(nsImage: cachedPixelated), in: CGRect(origin: .zero, size: size))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Dimension Badge
    private func dimensionBadge(for rect: CGRect, in viewSize: CGSize) -> some View {
        let pixelW = Int(rect.width * CGFloat(capturedCGImage.width) / viewSize.width)
        let pixelH = Int(rect.height * CGFloat(capturedCGImage.height) / viewSize.height)

        return Text("\(pixelW) × \(pixelH)")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.72))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            )
            .position(
                x: min(max(rect.maxX - 44, 44), viewSize.width - 44),
                y: rect.minY < 30 ? rect.minY + 16 : rect.minY - 14
            )
            .allowsHitTesting(false)
    }

    // MARK: - Floating HUD Capsule Toolbar (Attached to Selection)
    private func floatingHUD(for rect: CGRect, in viewSize: CGSize) -> some View {
        let (hudY, propY) = calculateHUDPosition(for: rect, viewSize: viewSize)
        let hudX = min(max(rect.midX, 230), viewSize.width - 230)

        return VStack(spacing: 6) {
            // Main HUD Capsule
            HStack(spacing: 3) {
                // 7 Drawing Tools
                ForEach([ScreenshotTool.rectangle, .ellipse, .arrow, .line, .pen, .text, .mosaic]) { tool in
                    hudToolButton(tool)
                }

                // Vertical Divider
                Capsule().fill(Color.white.opacity(0.2)).frame(width: 1, height: 16).padding(.horizontal, 4)

                // OCR Button
                Button {
                    triggerOCR(rect: rect, viewSize: viewSize)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 12, weight: .semibold))
                        Text("识图文字")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(isProcessingOCR ? Color.accentColor : Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        isProcessingOCR ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isProcessingOCR)
                .help("识别选区文字 (OCR)")

                // Vertical Divider
                Capsule().fill(Color.white.opacity(0.2)).frame(width: 1, height: 16).padding(.horizontal, 4)

                // Cancel Button
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .help("取消 (ESC)")

                // Done Button (Prominent Accent Circle)
                Button {
                    confirmCapture(rect: rect, viewSize: viewSize, isQuick: true)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.accentColor, in: Circle())
                }
                .buttonStyle(.plain)
                .help("完成并复制 (Return)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 19)
                    .fill(Color(nsColor: .black).opacity(0.78))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 19))
                    .overlay(
                        RoundedRectangle(cornerRadius: 19)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 12, y: 4)
            )

            // Secondary Properties Bar (Swatches, Stroke Width, Undo/Redo)
            if currentTool != nil {
                secondaryPropertiesBar
            }
        }
        .position(x: hudX, y: hudY)
    }

    private func hudToolButton(_ tool: ScreenshotTool) -> some View {
        let isActive = currentTool == tool
        return Button {
            if currentTool == tool {
                currentTool = nil // Deselect tool to return to move/cursor mode
            } else {
                currentTool = tool
            }
        } label: {
            Image(systemName: tool.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? .white : .white.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(
                    isActive ? Color.accentColor : Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 7)
                )
        }
        .buttonStyle(.plain)
        .help(tool.title)
    }

    // MARK: - Secondary Properties Bar
    private var secondaryPropertiesBar: some View {
        HStack(spacing: 8) {
            // Swatches
            HStack(spacing: 5) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { idx, swatch in
                    Button {
                        colorIndex = idx
                    } label: {
                        Circle()
                            .fill(swatch)
                            .frame(width: 15, height: 15)
                            .overlay(
                                Circle().strokeBorder(Color.white, lineWidth: colorIndex == idx ? 2 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Capsule().fill(Color.white.opacity(0.2)).frame(width: 1, height: 12).padding(.horizontal, 2)

            // Line Widths
            HStack(spacing: 4) {
                ForEach([CGFloat(2), CGFloat(3.5), CGFloat(6)], id: \.self) { width in
                    Button {
                        lineWidth = width
                    } label: {
                        Circle()
                            .fill(lineWidth == width ? Color.white : Color.white.opacity(0.4))
                            .frame(width: width + 2, height: width + 2)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("线条粗细 \(Int(width))pt")
                }
            }

            if currentTool == .text {
                Capsule().fill(Color.white.opacity(0.2)).frame(width: 1, height: 12).padding(.horizontal, 2)
                TextField("标注文字", text: $textInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .frame(width: 90)
            }

            Capsule().fill(Color.white.opacity(0.2)).frame(width: 1, height: 12).padding(.horizontal, 2)

            // Undo & Redo
            Button { undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(history.isEmpty ? Color.white.opacity(0.3) : Color.white)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(history.isEmpty)
            .help("撤销 (⌘Z)")

            Button { redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(undone.isEmpty ? Color.white.opacity(0.3) : Color.white)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(undone.isEmpty)
            .help("重做 (⇧⌘Z)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .black).opacity(0.82))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.75)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 8, y: 3)
        )
    }

    private func calculateHUDPosition(for rect: CGRect, viewSize: CGSize) -> (hudY: CGFloat, propY: CGFloat) {
        let totalHeight: CGFloat = currentTool != nil ? 78 : 42
        let margin: CGFloat = 10
        let spaceBelow = viewSize.height - rect.maxY

        if spaceBelow >= totalHeight + margin + 10 {
            // Display below selection
            let hudY = rect.maxY + margin + totalHeight / 2
            return (hudY, hudY + 22)
        } else {
            // Flip above selection
            let hudY = max(rect.minY - margin - totalHeight / 2, totalHeight / 2 + 10)
            return (hudY, hudY - 22)
        }
    }

    // MARK: - Top Pill Bar
    private func topPillBar(in viewSize: CGSize) -> some View {
        HStack(spacing: 8) {
            // Branding
            HStack(spacing: 5) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("PasteLoom")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 4)

            Capsule().fill(Color.white.opacity(0.2)).frame(width: 1, height: 14)

            // Pin Button (贴图)
            Button {
                pinCurrentSelection(in: viewSize)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pin")
                        .font(.system(size: 11, weight: .medium))
                    Text("贴图")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("将当前选区作为浮动便签贴在桌面")

            // Full Screen Button (全选屏)
            Button {
                selectAllScreen(in: viewSize)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "display")
                        .font(.system(size: 11, weight: .medium))
                    Text("全选屏")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("选择整个屏幕")

            Capsule().fill(Color.white.opacity(0.2)).frame(width: 1, height: 14)

            // Close Button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("退出截图 (ESC)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(nsColor: .black).opacity(0.78))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 10, y: 3)
        )
        .position(x: viewSize.width / 2, y: 28)
    }

    // MARK: - Window Candidate Snap Views
    @ViewBuilder
    private func candidateHighlightView(for target: DetectedWindowCandidate, in viewSize: CGSize) -> some View {
        // Spotlight cutout over candidate window
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.35)))
            context.blendMode = .clear
            context.fill(Path(roundedRect: target.rect, cornerRadius: 8), with: .color(.white))
        }
        .allowsHitTesting(false)

        // Accent border & glowing backdrop
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.accentColor, lineWidth: 2.5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.04))
            )
            .shadow(color: Color.accentColor.opacity(0.45), radius: 8, x: 0, y: 0)
            .frame(width: target.rect.width, height: target.rect.height)
            .position(x: target.rect.midX, y: target.rect.midY)
            .allowsHitTesting(false)

        // Window Info Badge
        candidateInfoBadge(for: target, in: viewSize)
    }

    private func candidateInfoBadge(for target: DetectedWindowCandidate, in viewSize: CGSize) -> some View {
        let badgeY = target.rect.minY > 44 ? target.rect.minY - 18 : min(target.rect.minY + 24, viewSize.height - 30)
        let badgeX = min(max(target.rect.midX, 180), viewSize.width - 180)

        return HStack(spacing: 6) {
            Image(systemName: "macwindow")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(target.appName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)

            if !target.windowTitle.isEmpty && target.windowTitle != target.appName {
                Text(target.windowTitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 160, alignment: .leading)
            }

            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 1, height: 10)

            Text("\(Int(target.rect.width)) × \(Int(target.rect.height))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))

            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 1, height: 10)

            Text("单击选取 · 空格")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(nsColor: .black).opacity(0.82))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 8, y: 3)
        )
        .position(x: badgeX, y: badgeY)
        .allowsHitTesting(false)
    }

    private func guideHintBadge(in viewSize: CGSize) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.tap")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text("移动鼠标自动吸附窗口 · 拖拽自由选区")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.72))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
        )
        .position(x: viewSize.width / 2, y: 58)
        .allowsHitTesting(false)
    }

    // MARK: - Actions & Rendering
    private func recordEdit() {
        history.append(marks)
        undone.removeAll()
    }

    private func undo() {
        guard let prev = history.popLast() else { return }
        undone.append(marks)
        marks = prev
    }

    private func redo() {
        guard let next = undone.popLast() else { return }
        history.append(marks)
        marks = next
    }

    private func selectAllScreen(in viewSize: CGSize) {
        selectedRect = CGRect(origin: .zero, size: viewSize)
        updatePixelatedCrop(rect: selectedRect!, viewSize: viewSize)
    }

    private func updatePixelatedCrop(rect: CGRect, viewSize: CGSize) {
        let scaleX = CGFloat(capturedCGImage.width) / viewSize.width
        let scaleY = CGFloat(capturedCGImage.height) / viewSize.height
        let pixelRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.size.width * scaleX,
            height: rect.size.height * scaleY
        ).integral
        guard let cropped = capturedCGImage.cropping(to: pixelRect) else { return }
        let rep = NSBitmapImageRep(cgImage: cropped)
        let img = NSImage(size: NSSize(width: rect.width, height: rect.height))
        img.addRepresentation(rep)
        cachedPixelated = ScreenshotAnnotationRenderer.pixelatedImage(from: img, pixelSize: rect.size)
    }

    private func confirmCapture(rect: CGRect, viewSize: CGSize, isQuick: Bool) {
        guard rect.width > 2 && rect.height > 2 else { return }
        let scaleX = CGFloat(capturedCGImage.width) / viewSize.width
        let scaleY = CGFloat(capturedCGImage.height) / viewSize.height
        let pixelRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.size.width * scaleX,
            height: rect.size.height * scaleY
        ).integral

        guard let cropped = capturedCGImage.cropping(to: pixelRect) else { return }
        let rep = NSBitmapImageRep(cgImage: cropped)
        guard let basePngData = rep.representation(using: .png, properties: [:]) else { return }

        // Render marks if any
        let finalPngData: Data
        if marks.isEmpty {
            finalPngData = basePngData
        } else {
            finalPngData = ScreenshotAnnotationRenderer.renderPNG(
                source: basePngData,
                marks: marks,
                crop: nil,
                colors: swatches,
                pixelated: cachedPixelated
            ) ?? basePngData
        }

        let document = ScreenshotDocument(pngData: finalPngData)
        onComplete(document, isQuick)
    }

    private func pinCurrentSelection(in viewSize: CGSize) {
        guard let rect = selectedRect ?? CGRect(origin: .zero, size: viewSize) as CGRect? else { return }
        let scaleX = CGFloat(capturedCGImage.width) / viewSize.width
        let scaleY = CGFloat(capturedCGImage.height) / viewSize.height
        let pixelRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.size.width * scaleX,
            height: rect.size.height * scaleY
        ).integral

        guard let cropped = capturedCGImage.cropping(to: pixelRect) else { return }
        let rep = NSBitmapImageRep(cgImage: cropped)
        guard let basePngData = rep.representation(using: .png, properties: [:]) else { return }

        let finalPngData: Data
        if marks.isEmpty {
            finalPngData = basePngData
        } else {
            finalPngData = ScreenshotAnnotationRenderer.renderPNG(
                source: basePngData,
                marks: marks,
                crop: nil,
                colors: swatches,
                pixelated: cachedPixelated
            ) ?? basePngData
        }

        if let image = NSImage(data: finalPngData) {
            // Convert to screen coordinates
            let screenOrigin = screen.frame.origin
            let flippedY = screenOrigin.y + (screen.frame.height - rect.maxY)
            let screenRect = NSRect(x: screenOrigin.x + rect.minX, y: flippedY,
                                    width: rect.width, height: rect.height)
            PinnedScreenshotWindowController.shared.pin(image: image, at: screenRect)
        }
        onDismiss()
    }

    private func triggerOCR(rect: CGRect, viewSize: CGSize) {
        let scaleX = CGFloat(capturedCGImage.width) / viewSize.width
        let scaleY = CGFloat(capturedCGImage.height) / viewSize.height
        let pixelRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.size.width * scaleX,
            height: rect.size.height * scaleY
        ).integral

        guard let cropped = capturedCGImage.cropping(to: pixelRect) else { return }
        let rep = NSBitmapImageRep(cgImage: cropped)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return }

        isProcessingOCR = true
        Task {
            defer { isProcessingOCR = false }
            do {
                let text = try await VisionOCRService.shared.recognizeText(from: pngData)
                ocrTextResult = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "未能识别到有效文字。" : text
                showOCRSheet = true
            } catch {
                ocrTextResult = "识别失败：\(error.localizedDescription)"
                showOCRSheet = true
            }
        }
    }

    // MARK: - OCR Result Modal
    private var ocrSheetView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "text.viewfinder")
                        .foregroundStyle(Color.accentColor)
                    Text("选区文字识别 (OCR)").font(.headline)
                }
                Spacer()
                if let text = ocrTextResult, !text.isEmpty {
                    Text("\(text.count) 字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("复制并关闭") {
                    if let text = ocrTextResult {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(text, forType: .string)
                    }
                    showOCRSheet = false
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)

                Button("关闭") { showOCRSheet = false }
            }

            ScrollView {
                Text(ocrTextResult ?? "")
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 180, maxHeight: 320)
            .padding(12)
            .background(Color(NSColor.textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(minWidth: 480)
    }
}
