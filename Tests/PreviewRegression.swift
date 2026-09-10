import AppKit

@main
struct PreviewRegression {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func image(width: Int, height: Int, retina: Bool = false) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let size = NSSize(width: retina ? width / 2 : width, height: retina ? height / 2 : height)
        rep.size = size
        let result = NSImage(size: size)
        result.addRepresentation(rep)
        return result
    }

    static func event(_ type: NSEvent.EventType, _ point: CGPoint, in view: NSView,
                      flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: flags,
                          timestamp: 0, windowNumber: view.window?.windowNumber ?? 0,
                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    static func drag(_ canvas: AnnotationCanvasView, from: CGPoint, to: CGPoint,
                     flags: NSEvent.ModifierFlags = []) {
        canvas.mouseDown(with: event(.leftMouseDown, from, in: canvas, flags: flags))
        canvas.mouseDragged(with: event(.leftMouseDragged, to, in: canvas, flags: flags))
        canvas.mouseUp(with: event(.leftMouseUp, to, in: canvas, flags: flags))
    }

    static func key(_ character: String, code: UInt16, flags: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)!
    }

    static func snapshot(_ window: NSWindow, name: String) {
        guard let directory = ProcessInfo.processInfo.environment["PREVIEW_ARTIFACT_DIR"],
              let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        // The content view is transparent; composite its cache onto the actual window color.
        let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: bitmap.pixelsWide,
            pixelsHigh: bitmap.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
        let rect = NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        window.backgroundColor.setFill()
        rect.fill()
        bitmap.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        try! output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let source = image(width: 600, height: 400, retina: true)
        let canvas = AnnotationCanvasView(image: source)
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                            styleMask: [.titled], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.contentView = canvas
        canvas.setFrameSize(NSSize(width: 600, height: 400))
        require(canvas.pixelSize == NSSize(width: 600, height: 400), "Retina dimensions lost")
        canvas.tool = .redact
        drag(canvas, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 220, y: 220))
        let redacted = canvas.renderedBitmap()!
        require(redacted.pixelsWide == 600 && redacted.pixelsHigh == 400, "Wrong export dimensions")
        let black = redacted.colorAt(x: 150, y: 250)!.usingColorSpace(.deviceRGB)!
        require(black.redComponent < 0.01 && black.greenComponent < 0.01 && black.blueComponent < 0.01 && black.alphaComponent == 1, "Redaction is not opaque black")
        let white = redacted.colorAt(x: 20, y: 20)!.usingColorSpace(.deviceRGB)!
        require(white.redComponent > 0.99, "Unredacted pixels changed")
        let beforeResize = canvas.pngData()!
        canvas.setFrameSize(NSSize(width: 1200, height: 800))
        canvas.displayScale = 2
        require(canvas.pngData() == beforeResize, "Resizing changed exported pixels")
        canvas.displayScale = 0.5
        require(canvas.pngData() == beforeResize, "Zoom changed exported pixels")
        canvas.clear()
        require(!canvas.hasAnnotations && canvas.canUndo, "Clear must be undoable")
        canvas.undo()
        require(canvas.pngData() == beforeResize, "Undo clear did not restore annotations")
        canvas.redo()
        require(!canvas.hasAnnotations, "Redo clear failed")
        canvas.undo()
        canvas.undo()
        require(!canvas.hasAnnotations && canvas.canRedo, "Undo drawing failed")
        canvas.addText("Retina text", at: CGPoint(x: 20, y: 350))
        require(!canvas.canRedo && canvas.annotationCount == 1, "New edit should invalidate redo")
        canvas.tool = .pen
        canvas.setFrameSize(NSSize(width: 600, height: 400))
        canvas.displayScale = 1
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 20, y: 20), in: canvas))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 80, y: 80), in: canvas))
        require(canvas.hasPendingAnnotation, "Stroke did not start")
        let committed = canvas.pngData()
        canvas.cancelPendingAnnotation()
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 80, y: 80), in: canvas))
        require(canvas.annotationCount == 1 && canvas.pngData() == committed, "Cancelled stroke was committed/exported")
        for tool in [AnnotationTool.arrow, .rectangle, .ellipse, .highlighter, .pen] {
            canvas.tool = tool
            drag(canvas, from: CGPoint(x: 40, y: 40), to: CGPoint(x: 180, y: 180), flags: .shift)
        }
        require(canvas.annotationCount == 6, "A drawing tool failed to commit")
        let styled = canvas.pngData()
        canvas.displayScale = 0.25
        canvas.setFrameSize(NSSize(width: 200, height: 200))
        require(canvas.pngData() == styled, "Stroke style changed on resize")

        let preview = PreviewWindowController(image: image(width: 1600, height: 1000, retina: true))
        let window = preview.window!
        preview.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        let editorCanvas = (window.contentView!.subviews.compactMap { $0 as? NSScrollView }.first!.documentView as! AnnotationCanvasView)
        editorCanvas.addText("Preview check", at: CGPoint(x: 80, y: 900))
        editorCanvas.tool = .rectangle
        let imageRect = editorCanvas.imageRect
        drag(editorCanvas, from: CGPoint(x: imageRect.midX, y: imageRect.midY),
             to: CGPoint(x: imageRect.midX + 60, y: imageRect.midY + 35))
        for size in [NSSize(width: 640, height: 340), NSSize(width: 1050, height: 700)] {
            window.setContentSize(size)
            window.contentView!.layoutSubtreeIfNeeded()
            preview.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window))
            let root = window.contentView!
            snapshot(window, name: "preview-\(Int(size.width)).png")
            for child in root.subviews {
                require(root.bounds.insetBy(dx: -1, dy: -1).contains(child.frame), "Preview content extends outside window")
                if let stack = child as? NSStackView {
                    for control in stack.arrangedSubviews where control is NSControl {
                        require(stack.bounds.insetBy(dx: -1, dy: -1).contains(control.alignmentRect(forFrame: control.frame)), "Toolbar control clipped: \(type(of: control)) frame=\(control.frame), alignment=\(control.alignmentRect(forFrame: control.frame)), stack=\(stack.bounds), superview=\(String(describing: control.superview))")
                    }
                }
            }
        }
        require(window.performKeyEquivalent(with: key("c", code: 8, flags: .command, window: window)), "Copy shortcut not handled")
        let copied = NSBitmapImageRep(data: NSPasteboard.general.data(forType: .png)!)!
        require(copied.pixelsWide == 1600 && copied.pixelsHigh == 1000, "Clipboard lost source pixels")
        require(window.performKeyEquivalent(with: key("1", code: 18, flags: .command, window: window)), "100% shortcut failed")
        require(window.performKeyEquivalent(with: key("0", code: 29, flags: .command, window: window)), "Fit shortcut failed")
        preview.close()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        host.close()
        print("PASS: Retina export, opaque redaction, zoom/resize invariance, undo/redo/clear, cancelled strokes, all drawing tools, small/large layout, clipboard and zoom shortcuts")
    }
}
