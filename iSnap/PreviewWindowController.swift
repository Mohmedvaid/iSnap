import AppKit
import UniformTypeIdentifiers

private final class PreviewWindow: NSWindow {
    var copyAction: (() -> Void)?
    var undoAction: (() -> Void)?
    var redoAction: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
            return
        }

        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            copyAction?()
            return
        }

        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            if event.modifierFlags.contains(.shift) {
                redoAction?()
            } else {
                undoAction?()
            }
            return
        }

        super.keyDown(with: event)
    }
}

final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    private let canvas: AnnotationCanvasView
    private let copyButton = NSButton()
    private let undoButton = NSButton()
    private let redoButton = NSButton()
    private let clearButton = NSButton()
    var onClose: (() -> Void)?

    init(image: NSImage) {
        canvas = AnnotationCanvasView(image: image)

        let window = PreviewWindow(
            contentRect: Self.windowFrame(for: image),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)
        configureWindow(window)
        buildContent(in: window)
        window.copyAction = { [weak self] in self?.copyImage() }
        window.undoAction = { [weak self] in self?.undo() }
        window.redoAction = { [weak self] in self?.redo() }
        window.initialFirstResponder = canvas
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func configureWindow(_ window: NSWindow) {
        window.title = "iSnap Editor"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        // Keep image drags available to the annotation canvas. The title bar
        // remains draggable when the user wants to move the editor window.
        window.isMovableByWindowBackground = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 420, height: 280)
        window.center()
    }

    private func buildContent(in window: NSWindow) {
        let root = NSVisualEffectView()
        root.material = .underWindowBackground
        root.blendingMode = .behindWindow
        root.state = .active
        root.translatesAutoresizingMaskIntoConstraints = false

        let toolSelector = NSSegmentedControl(
            labels: ["Arrow", "Rectangle", "Highlight"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(toolChanged(_:))
        )
        toolSelector.selectedSegment = AnnotationTool.arrow.rawValue
        toolSelector.segmentStyle = .rounded
        toolSelector.setWidth(72, forSegment: AnnotationTool.arrow.rawValue)
        toolSelector.setWidth(88, forSegment: AnnotationTool.rectangle.rawValue)
        toolSelector.setWidth(82, forSegment: AnnotationTool.highlighter.rawValue)

        configureToolbarButton(
            undoButton,
            symbolName: "arrow.uturn.backward",
            accessibilityLabel: "Undo",
            action: #selector(undo)
        )
        configureToolbarButton(
            redoButton,
            symbolName: "arrow.uturn.forward",
            accessibilityLabel: "Redo",
            action: #selector(redo)
        )

        clearButton.title = "Clear"
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearAnnotations)

        let toolbarSpacer = NSView()
        toolbarSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let toolbar = NSStackView(views: [toolSelector, toolbarSpacer, undoButton, redoButton, clearButton])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        copyButton.title = "Copy"
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "\r"
        copyButton.target = self
        copyButton.action = #selector(copyImage)

        let saveButton = NSButton(title: "Save…", target: self, action: #selector(saveImage))
        saveButton.bezelStyle = .rounded

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closePreview))
        closeButton.bezelStyle = .rounded

        let hint = NSTextField(labelWithString: "Drag to annotate   •   ⌘Z undo   •   ⌘C copy   •   Esc close")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [hint, spacer, closeButton, saveButton, copyButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10
        actions.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(toolbar)
        root.addSubview(canvas)
        root.addSubview(separator)
        root.addSubview(actions)
        window.contentView = root

        canvas.onHistoryChange = { [weak self] in
            self?.updateHistoryButtons()
        }
        updateHistoryButtons()

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            toolbar.heightAnchor.constraint(equalToConstant: 30),

            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            canvas.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -14),

            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -10),

            actions.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            actions.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            actions.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            actions.heightAnchor.constraint(equalToConstant: 30),

            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 20)
        ])
    }

    private func configureToolbarButton(
        _ button: NSButton,
        symbolName: String,
        accessibilityLabel: String,
        action: Selector
    ) {
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.target = self
        button.action = action
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
    }

    private func updateHistoryButtons() {
        undoButton.isEnabled = canvas.canUndo
        redoButton.isEnabled = canvas.canRedo
        clearButton.isEnabled = canvas.canUndo
    }

    @objc private func toolChanged(_ sender: NSSegmentedControl) {
        guard let tool = AnnotationTool(rawValue: sender.selectedSegment) else { return }
        canvas.tool = tool
    }

    @objc private func undo() {
        canvas.undo()
    }

    @objc private func redo() {
        canvas.redo()
    }

    @objc private func clearAnnotations() {
        canvas.clear()
    }

    @objc private func copyImage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([canvas.renderedImage()])

        copyButton.title = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.copyButton.title = "Copy"
        }
    }

    @objc private func closePreview() {
        close()
    }

    @objc private func saveImage() {
        guard let window else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = Self.defaultFileName()

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK,
                  let destination = panel.url,
                  let image = self?.canvas.renderedImage(),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                return
            }

            do {
                try png.write(to: destination, options: .atomic)
            } catch {
                let alert = NSAlert(error: error)
                alert.beginSheetModal(for: window)
            }
        }
    }

    private static func windowFrame(for image: NSImage) -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let maxWidth = min(1_050, visibleFrame.width * 0.82)
        let maxImageHeight = min(700, visibleFrame.height * 0.72)
        let imageSize = image.size

        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSRect(x: 0, y: 0, width: 700, height: 500)
        }

        let scale = min(maxWidth / imageSize.width, maxImageHeight / imageSize.height, 1)
        let width = max(480, imageSize.width * scale + 36)
        let height = max(360, imageSize.height * scale + 144)
        return NSRect(x: 0, y: 0, width: width, height: height)
    }

    private static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "iSnap \(formatter.string(from: Date())).png"
    }
}
