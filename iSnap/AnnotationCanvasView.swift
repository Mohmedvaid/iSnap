import AppKit

enum AnnotationTool: Int, CaseIterable {
    case arrow, rectangle, highlighter, pen, ellipse, text, redact

    var title: String {
        ["Arrow", "Rectangle", "Highlight", "Pen", "Oval", "Text", "Redact"][rawValue]
    }

    var symbol: String {
        ["arrow.up.right", "rectangle", "highlighter", "pencil.tip", "oval", "textformat", "rectangle.fill"][rawValue]
    }

    var shortcut: String { ["a", "r", "h", "p", "o", "t", "x"][rawValue] }

    var hint: String {
        switch self {
        case .arrow: return "Drag an arrow. Hold Shift to snap its angle."
        case .rectangle: return "Drag a rectangle. Hold Shift for a square."
        case .highlighter: return "Drag to highlight. Color and size apply to new strokes."
        case .pen: return "Draw freely. Color and size apply to new strokes."
        case .ellipse: return "Drag an oval. Hold Shift for a circle."
        case .text: return "Click the image to add a text label."
        case .redact: return "Drag a solid black box over information to hide."
        }
    }
}

private struct Annotation {
    let tool: AnnotationTool
    var points: [CGPoint]
    let color: NSColor
    // All geometry and styles are in source pixels, independent of window size/zoom.
    let width: CGFloat
    var text: String = ""
}

final class AnnotationCanvasView: NSView {
    let sourceImage: NSImage
    let pixelSize: NSSize
    var onHistoryChange: (() -> Void)?
    var onTextRequest: ((CGPoint) -> Void)?
    var inkColor = NSColor.systemRed
    var strokeWidth: CGFloat = 4
    var displayScale: CGFloat = 1 {
        didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) }
    }
    var tool: AnnotationTool = .arrow {
        didSet { cancelPendingAnnotation(); window?.makeFirstResponder(self) }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasAnnotations: Bool { !annotations.isEmpty }
    var annotationCount: Int { annotations.count }
    var hasPendingAnnotation: Bool { pending != nil }

    private var annotations: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    private var pending: Annotation?

    init(image: NSImage) {
        // Preserve the largest bitmap representation, including Retina captures.
        let bitmap = image.representations.compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
        if let cgImage = bitmap?.cgImage ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            pixelSize = NSSize(width: cgImage.width, height: cgImage.height)
            sourceImage = NSImage(cgImage: cgImage, size: pixelSize)
        } else {
            pixelSize = NSSize(width: max(1, image.size.width), height: max(1, image.size.height))
            sourceImage = image
        }
        super.init(frame: NSRect(origin: .zero, size: pixelSize))
        setAccessibilityLabel("Screenshot annotation canvas")
        setAccessibilityHelp("Choose a tool, then drag on the screenshot. Escape cancels an unfinished stroke.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var imageRect: NSRect {
        let size = NSSize(width: pixelSize.width * displayScale, height: pixelSize.height * displayScale)
        return NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    override func resetCursorRects() { addCursorRect(imageRect, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: imageRect).addClip()
        let transform = AffineTransform(translationByX: imageRect.minX, byY: imageRect.minY)
        (transform as NSAffineTransform).concat()
        let scale = NSAffineTransform()
        scale.scale(by: displayScale)
        scale.concat()
        drawDocument(includePending: true)
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(point) else { return }
        window?.makeFirstResponder(self)
        let position = sourcePoint(point)
        if tool == .text { onTextRequest?(position); return }
        let color = tool == .redact ? NSColor.black : inkColor
        // Freeze width when the gesture begins; future resizing cannot change exports.
        pending = Annotation(tool: tool, points: [position, position], color: color,
                             width: strokeWidth / max(displayScale, 0.001))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) { updatePending(with: event) }

    override func mouseUp(with event: NSEvent) {
        updatePending(with: event)
        guard let annotation = pending else { return }
        pending = nil
        let first = annotation.points[0]
        let last = annotation.points[annotation.points.count - 1]
        let distance = hypot(last.x - first.x, last.y - first.y) * displayScale
        let isFreehand = annotation.tool == .pen || annotation.tool == .highlighter
        let isArea = [.rectangle, .ellipse, .redact].contains(annotation.tool)
        let hasArea = abs(last.x - first.x) * displayScale >= 2 && abs(last.y - first.y) * displayScale >= 2
        if (isFreehand && annotation.points.count > 2) || (distance >= 2 && (!isArea || hasArea)) {
            commit { annotations.append(annotation) }
        }
        needsDisplay = true
    }

    private func updatePending(with event: NSEvent) {
        guard var annotation = pending else { return }
        var point = sourcePoint(convert(event.locationInWindow, from: nil))
        let start = annotation.points[0]
        if event.modifierFlags.contains(.shift) {
            let dx = point.x - start.x, dy = point.y - start.y
            if annotation.tool == .arrow {
                let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
                let length = hypot(dx, dy)
                point = CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
            } else if annotation.tool == .rectangle || annotation.tool == .ellipse {
                // Limit both axes together so squares stay square at image edges.
                let availableX = dx < 0 ? start.x : pixelSize.width - start.x
                let availableY = dy < 0 ? start.y : pixelSize.height - start.y
                let side = min(abs(dx), abs(dy), availableX, availableY)
                point = CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
            }
        }
        point = clamp(point)
        if annotation.tool == .pen || annotation.tool == .highlighter {
            let last = annotation.points.last!
            if hypot(last.x - point.x, last.y - point.y) * displayScale >= 0.5 {
                annotation.points.append(point)
            }
        } else {
            annotation.points[1] = point
        }
        pending = annotation
        needsDisplay = true
    }

    func addText(_ text: String, at point: CGPoint) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let annotation = Annotation(tool: .text, points: [clamp(point)], color: inkColor,
                                    width: strokeWidth / max(displayScale, 0.001), text: text)
        commit { annotations.append(annotation) }
    }

    func cancelPendingAnnotation() { pending = nil; needsDisplay = true }

    private func commit(_ change: () -> Void) {
        undoStack.append(annotations)
        // Bound history metadata; screenshot pixels are never duplicated in history.
        if undoStack.count > 100 { undoStack.removeFirst() }
        change()
        redoStack.removeAll()
        needsDisplay = true
        onHistoryChange?()
    }

    func undo() {
        cancelPendingAnnotation()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        needsDisplay = true
        onHistoryChange?()
    }

    func redo() {
        cancelPendingAnnotation()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        needsDisplay = true
        onHistoryChange?()
    }

    func clear() {
        cancelPendingAnnotation()
        guard hasAnnotations else { return }
        commit { annotations.removeAll() }
    }

    func renderedBitmap() -> NSBitmapImageRep? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width), pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        bitmap.size = pixelSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        drawDocument(includePending: false)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    func pngData() -> Data? { renderedBitmap()?.representation(using: .png, properties: [:]) }

    private func drawDocument(includePending: Bool) {
        let rect = NSRect(origin: .zero, size: pixelSize)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        sourceImage.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
        for annotation in annotations { draw(annotation) }
        if includePending, let pending { draw(pending) }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func draw(_ annotation: Annotation) {
        guard let start = annotation.points.first, let end = annotation.points.last else { return }
        let rect = NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        let path = NSBezierPath()
        path.lineWidth = annotation.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        annotation.color.setStroke()
        switch annotation.tool {
        case .arrow:
            path.move(to: start); path.line(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let head = min(annotation.width * 3.5, hypot(end.x - start.x, end.y - start.y) * 0.4)
            for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                path.move(to: end)
                path.line(to: CGPoint(x: end.x - head * cos(angle + offset), y: end.y - head * sin(angle + offset)))
            }
            path.stroke()
        case .rectangle, .ellipse:
            if annotation.tool == .ellipse { path.appendOval(in: rect) } else { path.appendRect(rect) }
            path.stroke()
        case .highlighter, .pen:
            path.move(to: start)
            for point in annotation.points.dropFirst() { path.line(to: point) }
            if annotation.tool == .highlighter {
                path.lineWidth *= 4.5
                annotation.color.withAlphaComponent(0.35).setStroke()
            }
            path.stroke()
        case .redact:
            // Opaque fill is flattened into exported pixels. There is no blur to reverse.
            NSColor.black.setFill()
            rect.integral.fill()
        case .text:
            let font = NSFont.systemFont(ofSize: max(12, annotation.width * 5), weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: annotation.color]
            let string = annotation.text as NSString
            let size = string.size(withAttributes: attributes)
            let origin = CGPoint(x: max(0, min(start.x, pixelSize.width - size.width)),
                                 y: max(0, min(start.y - size.height, pixelSize.height - size.height)))
            string.draw(at: origin, withAttributes: attributes)
        }
    }

    private func sourcePoint(_ point: CGPoint) -> CGPoint {
        clamp(CGPoint(x: (point.x - imageRect.minX) / max(displayScale, 0.001),
                      y: (point.y - imageRect.minY) / max(displayScale, 0.001)))
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), pixelSize.width), y: min(max(point.y, 0), pixelSize.height))
    }
}
