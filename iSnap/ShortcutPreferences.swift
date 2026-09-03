import AppKit
import Carbon

enum ShortcutAction: String, CaseIterable, Codable, Hashable {
    case captureArea
    case captureFullScreen

    var id: UInt32 {
        switch self {
        case .captureArea: return 1
        case .captureFullScreen: return 2
        }
    }

    var title: String {
        switch self {
        case .captureArea: return "Capture Area"
        case .captureFullScreen: return "Capture Full Screen"
        }
    }

    var defaultShortcut: KeyboardShortcut {
        let modifiers: NSEvent.ModifierFlags
        modifiers = [.command, .option]

        switch self {
        case .captureArea:
            return KeyboardShortcut(keyCode: UInt32(kVK_ANSI_5), modifierFlags: modifiers, keyLabel: "5")
        case .captureFullScreen:
            return KeyboardShortcut(keyCode: UInt32(kVK_ANSI_6), modifierFlags: modifiers, keyLabel: "6")
        }
    }
}

struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifierFlagsRawValue: UInt
    let keyLabel: String

    init(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        self.modifierFlagsRawValue = modifierFlags.rawValue
        self.keyLabel = keyLabel
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifierFlags.contains(.command) { result |= UInt32(cmdKey) }
        if modifierFlags.contains(.option) { result |= UInt32(optionKey) }
        if modifierFlags.contains(.shift) { result |= UInt32(shiftKey) }
        if modifierFlags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    var displayName: String {
        var result = ""
        if modifierFlags.contains(.control) { result += "⌃" }
        if modifierFlags.contains(.option) { result += "⌥" }
        if modifierFlags.contains(.shift) { result += "⇧" }
        if modifierFlags.contains(.command) { result += "⌘" }
        return result + keyLabel
    }

    static func from(event: NSEvent) -> KeyboardShortcut? {
        let allowedModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        let modifiers = event.modifierFlags.intersection(allowedModifiers)
        guard !modifiers.isEmpty,
              let label = keyLabel(for: event),
              event.keyCode != UInt16(kVK_Escape) else {
            return nil
        }

        return KeyboardShortcut(
            keyCode: UInt32(event.keyCode),
            modifierFlags: modifiers,
            keyLabel: label
        )
    }

    private static func keyLabel(for event: NSEvent) -> String? {
        let specialKeys: [UInt16: String] = [
            UInt16(kVK_Return): "↩",
            UInt16(kVK_Tab): "⇥",
            UInt16(kVK_Space): "Space",
            UInt16(kVK_Delete): "⌫",
            UInt16(kVK_ForwardDelete): "⌦",
            UInt16(kVK_LeftArrow): "←",
            UInt16(kVK_RightArrow): "→",
            UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_UpArrow): "↑",
            UInt16(kVK_F1): "F1",
            UInt16(kVK_F2): "F2",
            UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4",
            UInt16(kVK_F5): "F5",
            UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7",
            UInt16(kVK_F8): "F8",
            UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10",
            UInt16(kVK_F11): "F11",
            UInt16(kVK_F12): "F12"
        ]

        if let specialKey = specialKeys[event.keyCode] {
            return specialKey
        }

        guard let characters = event.charactersIgnoringModifiers,
              !characters.isEmpty else {
            return nil
        }
        return characters.uppercased()
    }
}

final class ShortcutStore {
    private let defaults: UserDefaults
    private let storageKey = "customKeyboardShortcuts"
    private var storedShortcuts: [String: KeyboardShortcut]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: KeyboardShortcut].self, from: data) {
            storedShortcuts = decoded
        } else {
            storedShortcuts = [:]
        }
    }

    func shortcut(for action: ShortcutAction) -> KeyboardShortcut {
        storedShortcuts[action.rawValue] ?? action.defaultShortcut
    }

    func set(_ shortcut: KeyboardShortcut, for action: ShortcutAction) {
        storedShortcuts[action.rawValue] = shortcut
        persist()
    }

    func action(using shortcut: KeyboardShortcut, excluding excludedAction: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first {
            $0 != excludedAction && self.shortcut(for: $0) == shortcut
        }
    }

    func resetToDefaults() {
        storedShortcuts = [:]
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(storedShortcuts) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
