import AppKit
import UniformTypeIdentifiers

private final class PreviewWindow: NSWindow {
    var handleKey: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Let text-entry and save sheets own their editing shortcuts.
        if attachedSheet == nil, !(firstResponder is NSTextView), handleKey?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if attachedSheet == nil, handleKey?(event) == true { return }
        super.keyDown(with: event)
    }
}

final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    private let canvas: AnnotationCanvasView
    private let scrollView = NSScrollView()
    private let toolSelector = NSSegmentedControl()
    private let colorSelector = NSPopUpButton()
    private let widthSelector = NSPopUpButton()
    private let zoomLabel = NSTextField(labelWithString: "Fit")
    private let statusLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private let undoButton = NSButton()
    private let redoButton = NSButton()
    private let clearButton = NSButton()
    private var zoom: CGFloat? // nil = fit, otherwise image pixels per screen point
    private var feedbackWork: DispatchWorkItem?
    private static let colors: [(String, NSColor)] = [
        ("Red", .systemRed), ("Yellow", .systemYellow), ("Blue", .systemBlue),
        ("Green", .systemGreen), ("White", .white), ("Black", .black)
    ]
    private static let widths: [CGFloat] = [2, 4, 7]
    var onClose: (() -> Void)?

    init(image: NSImage) {
        canvas = AnnotationCanvasView(image: image)
        let window = PreviewWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "iSnap Editor"
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentMinSize = NSSize(width: 640, height: 340)
        window.delegate = self
        buildContent(in: window)
        window.handleKey = { [weak self] event in self?.handleKey(event) ?? false }
        window.initialFirstResponder = canvas
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let scale = min(1, (visible.width * 0.8 - 32) / canvas.pixelSize.width,
                        max(1, visible.height * 0.8 - 190) / canvas.pixelSize.height)
        let size = NSSize(width: max(640, min(1050, canvas.pixelSize.width * scale + 32)),
                          height: max(340, canvas.pixelSize.height * scale + 170))
        window.setContentSize(size)
        window.center()
        window.setFrame(window.frame.intersection(visible), display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        layoutCanvas()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        feedbackWork?.cancel()
        // Retain the controller until AppKit finishes processing the close event.
        DispatchQueue.main.async { [self] in onClose?() }
    }

    func windowDidResize(_ notification: Notification) { layoutCanvas() }

    private func buildContent(in window: NSWindow) {
        let root = NSView()
        window.contentView = root
        toolSelector.segmentCount = AnnotationTool.allCases.count
        toolSelector.trackingMode = .selectOne
        toolSelector.segmentStyle = .rounded
        toolSelector.target = self
        toolSelector.action = #selector(toolChanged)
        for tool in AnnotationTool.allCases {
            toolSelector.setImage(NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.title), forSegment: tool.rawValue)
            toolSelector.setWidth(36, forSegment: tool.rawValue)
            toolSelector.setToolTip("\(tool.title) (\(tool.shortcut.uppercased()))", forSegment: tool.rawValue)
        }
        toolSelector.setAccessibilityLabel("Annotation tool")
        toolSelector.selectedSegment = canvas.tool.rawValue
        configureIcon(undoButton, symbol: "arrow.uturn.backward", label: "Undo (⌘Z)", action: #selector(undo))
        configureIcon(redoButton, symbol: "arrow.uturn.forward", label: "Redo (⇧⌘Z)", action: #selector(redo))
        configureButton(clearButton, title: "Clear", action: #selector(clearAnnotations))
        clearButton.toolTip = "Clear all annotations (can be undone)"
        let top = row([toolSelector, spacer(), undoButton, redoButton, clearButton])

        colorSelector.addItems(withTitles: Self.colors.map { $0.0 })
        colorSelector.target = self
        colorSelector.action = #selector(colorChanged)
        colorSelector.setAccessibilityLabel("Annotation color")
        widthSelector.addItems(withTitles: ["Thin", "Medium", "Bold"])
        let savedWidth = UserDefaults.standard.integer(forKey: "editor.strokeWidthIndex")
        widthSelector.selectItem(at: UserDefaults.standard.object(forKey: "editor.strokeWidthIndex") == nil ? 1 : min(2, max(0, savedWidth)))
        canvas.strokeWidth = Self.widths[widthSelector.indexOfSelectedItem]
        widthSelector.target = self
        widthSelector.action = #selector(widthChanged)
        widthSelector.setAccessibilityLabel("Stroke thickness")
        let minus = NSButton(), plus = NSButton()
        configureIcon(minus, symbol: "minus.magnifyingglass", label: "Zoom out (⌘−)", action: #selector(zoomOut))
        configureIcon(plus, symbol: "plus.magnifyingglass", label: "Zoom in (⌘+)", action: #selector(zoomIn))
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.alignment = .center
        zoomLabel.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let fit = button("Fit", #selector(fitImage)), actual = button("100%", #selector(actualSize))
        fit.toolTip = "Fit to window (⌘0)"
        actual.toolTip = "One image pixel per screen point (⌘1)"
        let options = row([colorSelector, widthSelector, spacer(), minus, zoomLabel, plus, fit, actual])

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .controlBackgroundColor
        scrollView.documentView = canvas

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configureButton(copyButton, title: "Copy", action: #selector(copyImage))
        copyButton.keyEquivalent = "\r"
        copyButton.toolTip = "Copy annotated image (⌘C or Return)"
        let copyClose = button("Copy & Close", #selector(copyAndClose))
        copyClose.toolTip = "Copy annotated image and close (⇧⌘C)"
        let save = button("Save…", #selector(saveImage))
        save.toolTip = "Save annotated PNG (⌘S)"
        let bottom = row([statusLabel, spacer(), save, copyButton, copyClose])

        for view in [top, options, hintLabel, scrollView, bottom] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            top.heightAnchor.constraint(equalToConstant: 30),
            options.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 6),
            options.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            options.trailingAnchor.constraint(equalTo: top.trailingAnchor),
            options.heightAnchor.constraint(equalToConstant: 28),
            hintLabel.topAnchor.constraint(equalTo: options.bottomAnchor, constant: 5),
            hintLabel.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: top.trailingAnchor),
            hintLabel.heightAnchor.constraint(equalToConstant: 16),
            scrollView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -10),
            bottom.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: top.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            bottom.heightAnchor.constraint(equalToConstant: 30)
        ])
        canvas.onHistoryChange = { [weak self] in self?.updateHistory() }
        canvas.onTextRequest = { [weak self] point in self?.promptForText(at: point) }
        updateToolOptions()
        updateHistory()
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        // Keep controls present; only the spacer and status text may compress.
        row.detachesHiddenViews = false
        return row
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 4).isActive = true
        return view
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let result = NSButton()
        configureButton(result, title: title, action: action)
        return result
    }

    private func configureButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func configureIcon(_ button: NSButton, symbol: String, label: String, action: Selector) {
        configureButton(button, title: "", action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
    }

    private func layoutCanvas() {
        guard scrollView.contentSize.width > 0, scrollView.contentSize.height > 0 else { return }
        let viewport = scrollView.contentSize
        let scale = zoom ?? min(1, max(1, viewport.width - 24) / canvas.pixelSize.width,
                               max(1, viewport.height - 24) / canvas.pixelSize.height)
        canvas.displayScale = scale
        canvas.setFrameSize(NSSize(width: max(viewport.width, canvas.pixelSize.width * scale),
                                   height: max(viewport.height, canvas.pixelSize.height * scale)))
        zoomLabel.stringValue = "\(zoom == nil ? "Fit · " : "")\(Int((scale * 100).rounded()))%"
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func setZoom(_ value: CGFloat?) {
        canvas.cancelPendingAnnotation()
        let old = scrollView.contentView.bounds
        let rect = canvas.imageRect
        let center = CGPoint(x: (old.midX - rect.minX) / canvas.displayScale,
                             y: (old.midY - rect.minY) / canvas.displayScale)
        zoom = value.map { min(8, max(0.05, $0)) }
        layoutCanvas()
        let newRect = canvas.imageRect
        let proposed = NSRect(x: newRect.minX + center.x * canvas.displayScale - old.width / 2,
                              y: newRect.minY + center.y * canvas.displayScale - old.height / 2,
                              width: old.width, height: old.height)
        let clipped = scrollView.contentView.constrainBoundsRect(proposed)
        scrollView.contentView.scroll(to: clipped.origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        focusCanvas()
    }

    @objc private func zoomIn() { setZoom(canvas.displayScale * 1.25) }
    @objc private func zoomOut() { setZoom(canvas.displayScale / 1.25) }
    @objc private func fitImage() { setZoom(nil) }
    @objc private func actualSize() { setZoom(1) }
    private func focusCanvas() { window?.makeFirstResponder(canvas) }

    private func updateHistory() {
        undoButton.isEnabled = canvas.canUndo
        redoButton.isEnabled = canvas.canRedo
        clearButton.isEnabled = canvas.hasAnnotations
        feedbackWork?.cancel()
        copyButton.title = "Copy"
        statusLabel.stringValue = "\(Int(canvas.pixelSize.width)) × \(Int(canvas.pixelSize.height)) px · \(canvas.annotationCount) marks"
    }

    private var colorPreferenceKey: String {
        canvas.tool == .highlighter ? "editor.highlightColorIndex" : "editor.inkColorIndex"
    }

    private func updateToolOptions() {
        let stored = UserDefaults.standard.object(forKey: colorPreferenceKey) as? Int
        let index = min(Self.colors.count - 1, max(0, stored ?? (canvas.tool == .highlighter ? 1 : 0)))
        colorSelector.selectItem(at: index)
        canvas.inkColor = Self.colors[index].1
        colorSelector.isEnabled = canvas.tool != .redact
        widthSelector.isEnabled = canvas.tool != .redact
        hintLabel.stringValue = canvas.tool.hint
        hintLabel.toolTip = canvas.tool.hint
    }

    @objc private func toolChanged() {
        guard let tool = AnnotationTool(rawValue: toolSelector.selectedSegment) else { return }
        canvas.tool = tool
        updateToolOptions()
    }

    @objc private func colorChanged() {
        canvas.inkColor = Self.colors[colorSelector.indexOfSelectedItem].1
        UserDefaults.standard.set(colorSelector.indexOfSelectedItem, forKey: colorPreferenceKey)
        focusCanvas()
    }

    @objc private func widthChanged() {
        canvas.strokeWidth = Self.widths[widthSelector.indexOfSelectedItem]
        UserDefaults.standard.set(widthSelector.indexOfSelectedItem, forKey: "editor.strokeWidthIndex")
        focusCanvas()
    }

    @objc private func undo() { canvas.undo(); focusCanvas() }
    @objc private func redo() { canvas.redo(); focusCanvas() }
    @objc private func clearAnnotations() { canvas.clear(); focusCanvas() }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags.contains(.command), !flags.contains(.control), !flags.contains(.option) {
            switch key {
            case "c": if flags.contains(.shift) { copyAndClose() } else { copyImage() }
            case "s": saveImage()
            case "w": close()
            case "z": if flags.contains(.shift) { redo() } else { undo() }
            case "0": fitImage()
            case "1": actualSize()
            case "+", "=": zoomIn()
            case "-": zoomOut()
            default: return false
            }
            return true
        }
        guard flags.isEmpty else { return false }
        if event.keyCode == 53 {
            if canvas.hasPendingAnnotation { canvas.cancelPendingAnnotation() } else { close() }
            return true
        }
        if let tool = AnnotationTool.allCases.first(where: { $0.shortcut == key }) {
            toolSelector.selectedSegment = tool.rawValue
            toolChanged()
            return true
        }
        return false
    }

    private func promptForText(at point: CGPoint) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Add text"
        alert.informativeText = "Place a label on the screenshot using the selected color and size."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "Type your label"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.canvas.addText(field.stringValue, at: point) }
            self?.focusCanvas()
        }
    }

    @discardableResult private func writeClipboard() -> Bool {
        guard let bitmap = canvas.renderedBitmap(),
              let png = bitmap.representation(using: .png, properties: [:]),
              let tiff = bitmap.tiffRepresentation else {
            showError("The screenshot could not be rendered. Please try again.")
            return false
        }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else {
            showError("The screenshot could not be copied. Please try again.")
            return false
        }
        return true
    }

    @objc private func copyImage() {
        guard writeClipboard() else { return }
        feedbackWork?.cancel()
        copyButton.title = "Copied!"
        let work = DispatchWorkItem { [weak self] in self?.copyButton.title = "Copy" }
        feedbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        focusCanvas()
    }

    @objc private func copyAndClose() { if writeClipboard() { close() } }

    @objc private func saveImage() {
        guard let window, window.attachedSheet == nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        panel.nameFieldStringValue = "iSnap \(formatter.string(from: Date())).png"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            defer { self.focusCanvas() }
            guard response == .OK, let destination = panel.url else { return }
            guard let png = self.canvas.pngData() else {
                self.showError("The screenshot could not be rendered. Please try again.")
                return
            }
            do {
                try png.write(to: destination, options: .atomic)
                self.statusLabel.stringValue = "Saved \(destination.lastPathComponent)"
            } catch { self.showError(error.localizedDescription) }
        }
    }

    private func showError(_ message: String) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "iSnap couldn't finish that action"
        alert.informativeText = message
        alert.beginSheetModal(for: window)
    }
}
