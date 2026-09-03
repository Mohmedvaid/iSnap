import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let shortcutStore: ShortcutStore
    private var shortcutButtons: [ShortcutAction: NSButton] = [:]
    private var recordingAction: ShortcutAction?
    private var eventMonitor: Any?
    var onShortcutsChanged: (() -> Void)?

    init(shortcutStore: ShortcutStore) {
        self.shortcutStore = shortcutStore

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "iSnap Settings"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        refreshShortcutButtons()
        super.showWindow(sender)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        window?.makeKeyAndOrderFront(sender)
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }

    private func buildContent(in window: NSWindow) {
        let root = NSView()
        window.contentView = root

        let title = NSTextField(labelWithString: "Keyboard Shortcuts")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Click a shortcut, then press your new key combination.")
        subtitle.textColor = .secondaryLabelColor

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 10

        for action in ShortcutAction.allCases {
            rows.addArrangedSubview(makeRow(for: action))
        }

        let note = NSTextField(labelWithString: "Use at least one modifier key: Command, Option, Control, or Shift.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)

        let resetButton = NSButton(
            title: "Restore Defaults",
            target: self,
            action: #selector(resetShortcuts)
        )
        resetButton.bezelStyle = .rounded

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [note, footerSpacer, resetButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10

        let content = NSStackView(views: [title, subtitle, rows, footer])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            rows.widthAnchor.constraint(equalTo: content.widthAnchor),
            footer.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])
    }

    private func makeRow(for action: ShortcutAction) -> NSView {
        let label = NSTextField(labelWithString: action.title)
        label.font = .systemFont(ofSize: 13)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let button = NSButton(
            title: shortcutStore.shortcut(for: action).displayName,
            target: self,
            action: #selector(beginRecording(_:))
        )
        button.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
        button.bezelStyle = .rounded
        button.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        button.widthAnchor.constraint(equalToConstant: 150).isActive = true
        shortcutButtons[action] = button

        let row = NSStackView(views: [label, spacer, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.widthAnchor.constraint(equalToConstant: 492).isActive = true
        row.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return row
    }

    @objc private func beginRecording(_ sender: NSButton) {
        stopRecording()
        guard let identifier = sender.identifier?.rawValue,
              let action = ShortcutAction(rawValue: identifier) else {
            return
        }

        recordingAction = action
        sender.title = "Press shortcut…"
        sender.contentTintColor = .controlAccentColor

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecordedEvent(event)
            return nil
        }
    }

    private func handleRecordedEvent(_ event: NSEvent) {
        guard let action = recordingAction else { return }

        if event.keyCode == 53 {
            stopRecording()
            refreshShortcutButtons()
            return
        }

        guard let shortcut = KeyboardShortcut.from(event: event) else {
            NSSound.beep()
            shortcutButtons[action]?.title = "Add a modifier"
            return
        }

        if let conflictingAction = shortcutStore.action(using: shortcut, excluding: action) {
            NSSound.beep()
            shortcutButtons[action]?.title = "Already in use"
            showConflictAlert(shortcut: shortcut, action: conflictingAction)
            return
        }

        shortcutStore.set(shortcut, for: action)
        stopRecording()
        refreshShortcutButtons()
        onShortcutsChanged?()
    }

    private func showConflictAlert(shortcut: KeyboardShortcut, action: ShortcutAction) {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "That shortcut is already in use"
        alert.informativeText = "\(shortcut.displayName) is assigned to \(action.title). Choose another combination."
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { [weak self] _ in
            self?.stopRecording()
            self?.refreshShortcutButtons()
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        recordingAction = nil
        shortcutButtons.values.forEach { $0.contentTintColor = nil }
    }

    private func refreshShortcutButtons() {
        for action in ShortcutAction.allCases {
            shortcutButtons[action]?.title = shortcutStore.shortcut(for: action).displayName
        }
    }

    @objc private func resetShortcuts() {
        stopRecording()
        shortcutStore.resetToDefaults()
        refreshShortcutButtons()
        onShortcutsChanged?()
    }
}
