import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let screenshotController = ScreenshotController()
    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        registerGlobalShortcuts()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "iSnap"
            )
            button.toolTip = "iSnap"
        }

        let menu = NSMenu()
        menu.addItem(menuItem(
            title: "Capture Area",
            action: #selector(captureArea),
            key: "5",
            modifiers: [.command, .option]
        ))
        menu.addItem(menuItem(
            title: "Capture Full Screen",
            action: #selector(captureFullScreen),
            key: "6",
            modifiers: [.command, .option]
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            title: "Delayed Area (5 seconds)",
            action: #selector(captureDelayedArea),
            key: "5",
            modifiers: [.command, .option, .shift]
        ))
        menu.addItem(menuItem(
            title: "Delayed Full Screen (5 seconds)",
            action: #selector(captureDelayedFullScreen),
            key: "6",
            modifiers: [.command, .option, .shift]
        ))
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Open Screen Recording Settings…",
            action: #selector(openScreenRecordingSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit iSnap",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func registerGlobalShortcuts() {
        let baseModifiers = UInt32(cmdKey | optionKey)
        let delayedModifiers = UInt32(cmdKey | optionKey | shiftKey)

        hotKeyManager = HotKeyManager(shortcuts: [
            .init(
                id: 1,
                keyCode: UInt32(kVK_ANSI_5),
                modifiers: baseModifiers,
                action: { [weak self] in self?.captureArea() }
            ),
            .init(
                id: 2,
                keyCode: UInt32(kVK_ANSI_6),
                modifiers: baseModifiers,
                action: { [weak self] in self?.captureFullScreen() }
            ),
            .init(
                id: 3,
                keyCode: UInt32(kVK_ANSI_5),
                modifiers: delayedModifiers,
                action: { [weak self] in self?.captureDelayedArea() }
            ),
            .init(
                id: 4,
                keyCode: UInt32(kVK_ANSI_6),
                modifiers: delayedModifiers,
                action: { [weak self] in self?.captureDelayedFullScreen() }
            )
        ])
    }

    private func menuItem(
        title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    @objc private func captureArea() {
        screenshotController.capture(.area)
    }

    @objc private func captureFullScreen() {
        screenshotController.capture(.fullScreen)
    }

    @objc private func captureDelayedArea() {
        screenshotController.capture(.area, delay: 5)
    }

    @objc private func captureDelayedFullScreen() {
        screenshotController.capture(.fullScreen, delay: 5)
    }

    @objc private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

