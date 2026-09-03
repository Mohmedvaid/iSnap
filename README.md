# iSnap

iSnap is a tiny, local-only macOS screenshot utility built around one fast workflow:

1. Trigger a screenshot from anywhere.
2. Capture an area or the full main display.
3. The image opens immediately in an iSnap preview.
4. Press **Command-C** to copy it and **Escape** to close.

There are no accounts, uploads, annotations, or background services.

## Shortcuts

| Action | Global shortcut |
| --- | --- |
| Capture an area | Option-Command-5 |
| Capture the full main display | Option-Command-6 |
| Capture an area after 5 seconds | Shift-Option-Command-5 |
| Capture the full main display after 5 seconds | Shift-Option-Command-6 |

You can also trigger every action from the camera icon in the menu bar.

## Run it

1. Open `iSnap.xcodeproj` in Xcode 15 or newer.
2. Select the **iSnap** scheme and **My Mac** destination.
3. Press **Command-R**.
4. Approve Screen Recording access if macOS asks. If the first capture is blank, quit and reopen iSnap after granting permission.

iSnap is a menu-bar utility, so it intentionally does not appear in the Dock.

## How it works

iSnap uses macOS's built-in `/usr/sbin/screencapture` process for the native selection experience, then reads the resulting full-resolution image from the pasteboard. The app keeps only the current preview in memory unless you explicitly save it.

## Current scope

- Native area and full-screen capture
- Five-second delayed captures
- Global keyboard shortcuts
- Immediate lightweight preview
- Copy, save, and close actions
- Local-only operation

