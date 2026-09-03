import AppKit

enum AnnotationTool: Int {
    case arrow
    case rectangle
    case highlighter
}

private enum Annotation {
    case arrow(start: CGPoint, end: CGPoint)
    case rectangle(start: CGPoint, end: CGPoint)
    case highlight(points: [CGPoint])
}

final class AnnotationCanvasView: NSView {
    let sourceImage: NSImage
    var onHistoryChange: (() -> Void)?

    var tool: AnnotationTool = .arrow {
        didSet {
            discardPendingAnnotation()
            window?.makeFirstResponder(self)
        }
    }

    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private var annotations: [Annotation] = []
    private var redoStack: [Annotation] = []
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var highlightPoints: [CGPoint] = []

    init(image: NSImage) {
        sourceImage = image
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(imageRect, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        let destination = imageRect
        sourceImage.draw(
            in: destination,
            from: NSRect(origin: .zero, size: sourceImage.size),
            operation: .sourceOver,
            fraction: 1
        )

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: destination).addClip()
        Self.draw(annotations: annotations, in: destination, strokeScale: 1)
        if let pending = pendingAnnotation {
            Self.draw(annotation: pending, in: destination, strokeScale: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(point) else { return }

        window?.makeFirstResponder(self)
        let normalized = normalizedPoint(point)
        dragStart = normalized
        dragCurrent = normalized
        highlightPoints = tool == .highlighter ? [normalized] : []
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }

        let point = clampedToImage(convert(event.locationInWindow, from: nil))
        let normalized = normalizedPoint(point)
        dragCurrent = normalized

        if tool == .highlighter {
            if let last = highlightPoints.last,
               hypot(normalized.x - last.x, normalized.y - last.y) > 0.002 {
                highlightPoints.append(normalized)
            }
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }

        let point = clampedToImage(convert(event.locationInWindow, from: nil))
        dragCurrent = normalizedPoint(point)

        if let annotation = pendingAnnotation, isMeaningful(annotation) {
            annotations.append(annotation)
            redoStack.removeAll()
            onHistoryChange?()
        }

        discardPendingAnnotation()
    }

    func undo() {
        guard let annotation = annotations.popLast() else { return }
        redoStack.append(annotation)
        needsDisplay = true
        onHistoryChange?()
    }

    func redo() {
        guard let annotation = redoStack.popLast() else { return }
        annotations.append(annotation)
        needsDisplay = true
        onHistoryChange?()
    }

    func clear() {
        guard !annotations.isEmpty else { return }
        annotations.removeAll()
        redoStack.removeAll()
        needsDisplay = true
        onHistoryChange?()
    }

    func renderedImage() -> NSImage {
        let outputSize = sourceImage.size
        let displayWidth = max(imageRect.width, 1)
        let strokeScale = max(0.25, outputSize.width / displayWidth)
        let image = sourceImage
        let committedAnnotations = annotations

        return NSImage(size: outputSize, flipped: false) { outputRect in
            image.draw(
                in: outputRect,
                from: NSRect(origin: .zero, size: image.size),
                operation: .sourceOver,
                fraction: 1
            )
            Self.draw(annotations: committedAnnotations, in: outputRect, strokeScale: strokeScale)
            return true
        }
    }

    private var imageRect: NSRect {
        let size = sourceImage.size
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fittedSize = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(
            x: bounds.midX - fittedSize.width / 2,
            y: bounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private var pendingAnnotation: Annotation? {
        guard let start = dragStart, let current = dragCurrent else { return nil }

        switch tool {
        case .arrow:
            return .arrow(start: start, end: current)
        case .rectangle:
            return .rectangle(start: start, end: current)
        case .highlighter:
            return .highlight(points: highlightPoints + [current])
        }
    }

    private func discardPendingAnnotation() {
        dragStart = nil
        dragCurrent = nil
        highlightPoints.removeAll()
        needsDisplay = true
    }

    private func normalizedPoint(_ point: CGPoint) -> CGPoint {
        let rect = imageRect
        return CGPoint(
            x: (point.x - rect.minX) / max(rect.width, 1),
            y: (point.y - rect.minY) / max(rect.height, 1)
        )
    }

    private func clampedToImage(_ point: CGPoint) -> CGPoint {
        let rect = imageRect
        return CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func isMeaningful(_ annotation: Annotation) -> Bool {
        switch annotation {
        case let .arrow(start, end), let .rectangle(start, end):
            return hypot(end.x - start.x, end.y - start.y) > 0.005
        case let .highlight(points):
            guard let first = points.first, let last = points.last else { return false }
            return points.count > 2 || hypot(last.x - first.x, last.y - first.y) > 0.005
        }
    }

    private static func draw(annotations: [Annotation], in rect: NSRect, strokeScale: CGFloat) {
        for annotation in annotations {
            draw(annotation: annotation, in: rect, strokeScale: strokeScale)
        }
    }

    private static func draw(annotation: Annotation, in rect: NSRect, strokeScale: CGFloat) {
        switch annotation {
        case let .arrow(start, end):
            drawArrow(
                from: denormalizedPoint(start, in: rect),
                to: denormalizedPoint(end, in: rect),
                strokeScale: strokeScale
            )

        case let .rectangle(start, end):
            NSColor.systemRed.setStroke()
            let path = NSBezierPath(rect: rectBetween(
                denormalizedPoint(start, in: rect),
                denormalizedPoint(end, in: rect)
            ))
            path.lineWidth = 4 * strokeScale
            path.lineJoinStyle = .round
            path.stroke()

        case let .highlight(points):
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.move(to: denormalizedPoint(first, in: rect))
            for point in points.dropFirst() {
                path.line(to: denormalizedPoint(point, in: rect))
            }
            path.lineWidth = 18 * strokeScale
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.systemYellow.withAlphaComponent(0.38).setStroke()
            path.stroke()
        }
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, strokeScale: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = 4 * strokeScale
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = 14 * strokeScale
        let headAngle = CGFloat.pi / 6
        path.move(to: end)
        path.line(to: CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        ))
        path.move(to: end)
        path.line(to: CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        ))

        NSColor.systemRed.setStroke()
        path.stroke()
    }

    private static func denormalizedPoint(_ point: CGPoint, in rect: NSRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }

    private static func rectBetween(_ first: CGPoint, _ second: CGPoint) -> NSRect {
        NSRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }
}
