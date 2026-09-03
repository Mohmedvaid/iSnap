import AppKit
import UniformTypeIdentifiers

private final class PreviewWindow: NSWindow {
    var copyAction: (() -> Void)?

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

        super.keyDown(with: event)
    }
}

final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    private let image: NSImage
    private let copyButton = NSButton()
    var onClose: (() -> Void)?

    init(image: NSImage) {
        self.image = image

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
        window.title = "iSnap Preview"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = true
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

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false

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

        let hint = NSTextField(labelWithString: "⌘C copy   •   Esc close")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [hint, spacer, closeButton, saveButton, copyButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10
        actions.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(imageView)
        root.addSubview(separator)
        root.addSubview(actions)
        window.contentView = root

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            imageView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            imageView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            imageView.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -14),

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

    @objc private func copyImage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

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
                  let image = self?.image,
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
        let height = max(320, imageSize.height * scale + 100)
        return NSRect(x: 0, y: 0, width: width, height: height)
    }

    private static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "iSnap \(formatter.string(from: Date())).png"
    }
}
