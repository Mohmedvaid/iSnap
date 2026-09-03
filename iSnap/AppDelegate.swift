import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let screenshotController = ScreenshotController()
    private let shortcutStore = ShortcutStore()
    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private var settingsWindowController: SettingsWindowController?
    private var actionMenuItems: [ShortcutAction: NSMenuItem] = [:]

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
        menu.addItem(actionMenuItem(for: .captureArea, action: #selector(captureArea)))
        menu.addItem(actionMenuItem(for: .captureFullScreen, action: #selector(captureFullScreen)))
        menu.addItem(.separator())
        menu.addItem(actionMenuItem(for: .delayedArea, action: #selector(captureDelayedArea)))
        menu.addItem(actionMenuItem(for: .delayedFullScreen, action: #selector(captureDelayedFullScreen)))
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        let screenRecordingItem = NSMenuItem(
            title: "Open Screen Recording Settings…",
            action: #selector(openScreenRecordingSettings),
            keyEquivalent: ""
        )
        screenRecordingItem.target = self
        menu.addItem(screenRecordingItem)
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
        hotKeyManager = nil
        let actions: [ShortcutAction: () -> Void] = [
            .captureArea: { [weak self] in self?.captureArea() },
            .captureFullScreen: { [weak self] in self?.captureFullScreen() },
            .delayedArea: { [weak self] in self?.captureDelayedArea() },
            .delayedFullScreen: { [weak self] in self?.captureDelayedFullScreen() }
        ]

        let shortcuts: [HotKeyManager.Shortcut] = ShortcutAction.allCases.compactMap { action in
            guard let callback = actions[action] else { return nil }
            let shortcut = shortcutStore.shortcut(for: action)
            return HotKeyManager.Shortcut(
                id: action.id,
                keyCode: shortcut.keyCode,
                modifiers: shortcut.carbonModifiers,
                action: callback
            )
        }
        hotKeyManager = HotKeyManager(shortcuts: shortcuts)
        refreshMenuShortcutTitles()
    }

    private func actionMenuItem(for shortcutAction: ShortcutAction, action: Selector) -> NSMenuItem {
        let shortcut = shortcutStore.shortcut(for: shortcutAction)
        let item = NSMenuItem(
            title: "\(shortcutAction.title)    \(shortcut.displayName)",
            action: action,
            keyEquivalent: ""
        )
        item.target = self
        actionMenuItems[shortcutAction] = item
        return item
    }

    private func refreshMenuShortcutTitles() {
        for action in ShortcutAction.allCases {
            let shortcut = shortcutStore.shortcut(for: action)
            actionMenuItems[action]?.title = "\(action.title)    \(shortcut.displayName)"
        }
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

    @objc private func openSettings() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(shortcutStore: shortcutStore)
            controller.onShortcutsChanged = { [weak self] in
                self?.registerGlobalShortcuts()
            }
            settingsWindowController = controller
        }
        settingsWindowController?.showWindow(nil)
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
