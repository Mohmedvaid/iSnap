import AppKit

final class SelectionOverlayController {
    typealias Completion = (_ rect: CGRect?, _ useDelay: Bool) -> Void

    private var windows: [SelectionWindow] = []
    private var eventMonitor: Any?
    private var completion: Completion?
    private var pushedCursor = false

    func begin(completion: @escaping Completion) {
        self.completion = completion
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])

        for screen in NSScreen.screens {
            let window = SelectionWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.acceptsMouseMovedEvents = true

            let selectionView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            selectionView.screenFrame = screen.frame
            selectionView.coordinator = self
            window.contentView = selectionView
            window.orderFrontRegardless()
            windows.append(window)
        }

        NSCursor.crosshair.push()
        pushedCursor = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancel()
                return nil
            }
            return event
        }
    }

    fileprivate func complete(appKitRect: NSRect, useDelay: Bool) {
        let normalizedRect = appKitRect.standardized.integral
        guard normalizedRect.width >= 3, normalizedRect.height >= 3 else {
            cancel()
            return
        }

        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? normalizedRect.maxY
        let captureRect = CGRect(
            x: normalizedRect.minX,
            y: primaryScreenHeight - normalizedRect.maxY,
            width: normalizedRect.width,
            height: normalizedRect.height
        ).integral

        finish(rect: captureRect, useDelay: useDelay)
    }

    fileprivate func cancel() {
        finish(rect: nil, useDelay: false)
    }

    private func finish(rect: CGRect?, useDelay: Bool) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        windows.forEach { $0.close() }
        windows.removeAll()

        if pushedCursor {
            NSCursor.pop()
            pushedCursor = false
        }

        let callback = completion
        completion = nil
        callback?(rect, useDelay)
    }
}

private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SelectionView: NSView {
    weak var coordinator: SelectionOverlayController?
    var screenFrame = NSRect.zero

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var useDelay = false

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = globalPoint(for: event)
        startPoint = point
        currentPoint = point
        useDelay = event.modifierFlags.contains(.control)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = globalPoint(for: event)
        useDelay = useDelay || event.modifierFlags.contains(.control)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint else {
            coordinator?.cancel()
            return
        }

        let endPoint = globalPoint(for: event)
        useDelay = useDelay || event.modifierFlags.contains(.control)
        coordinator?.complete(
            appKitRect: NSRect(
                x: min(startPoint.x, endPoint.x),
                y: min(startPoint.y, endPoint.y),
                width: abs(endPoint.x - startPoint.x),
                height: abs(endPoint.y - startPoint.y)
            ),
            useDelay: useDelay
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()

        drawInstructions()

        guard let selection = localSelectionRect else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.setBlendMode(.clear)
        context.fill(selection)
        context.restoreGState()

        let borderColor: NSColor = useDelay ? .systemOrange : .controlAccentColor
        borderColor.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        border.stroke()

        drawSelectionLabel(for: selection, color: borderColor)
    }

    private var localSelectionRect: NSRect? {
        guard let startPoint, let currentPoint else { return nil }
        let globalRect = NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
        return globalRect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }

    private func globalPoint(for event: NSEvent) -> NSPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
    }

    private func drawInstructions() {
        let text = "Drag to capture  •  Hold Control while dragging for a 5-second delay  •  Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let renderedText = text as NSString
        let size = renderedText.size(withAttributes: attributes)
        let textRect = NSRect(
            x: max(20, (bounds.width - size.width) / 2),
            y: bounds.height - size.height - 28,
            width: size.width,
            height: size.height
        )
        renderedText.draw(in: textRect, withAttributes: attributes)
    }

    private func drawSelectionLabel(for selection: NSRect, color: NSColor) {
        let width = max(0, Int(selection.width.rounded()))
        let height = max(0, Int(selection.height.rounded()))
        let text = useDelay ? "\(width) × \(height)  •  5s delay" : "\(width) × \(height)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let renderedText = text as NSString
        let textSize = renderedText.size(withAttributes: attributes)
        let labelSize = NSSize(width: textSize.width + 16, height: textSize.height + 10)
        var labelOrigin = NSPoint(x: selection.minX, y: selection.minY - labelSize.height - 6)
        if labelOrigin.y < 8 {
            labelOrigin.y = selection.maxY + 6
        }
        labelOrigin.x = min(max(8, labelOrigin.x), bounds.width - labelSize.width - 8)

        let labelRect = NSRect(origin: labelOrigin, size: labelSize)
        color.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6).fill()
        renderedText.draw(
            at: NSPoint(x: labelRect.minX + 8, y: labelRect.minY + 5),
            withAttributes: attributes
        )
    }
}
