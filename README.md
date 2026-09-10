# iSnap

iSnap is a tiny, local-only macOS screenshot utility built around one fast workflow:

1. Trigger a screenshot from anywhere.
2. Capture an area or the full main display.
3. The image opens immediately in an iSnap preview.
4. Press **Command-C** to copy it and **Escape** to close.

There are no accounts, uploads, or background services.

The preview also includes red arrows, red rectangles, and a translucent highlighter.
Annotations are flattened into the image
when you copy or save it, and can be undone with **Command-Z**.

## Shortcuts

| Action | Global shortcut |
| --- | --- |
| Capture an area | Option-Command-5 |
| Capture the full main display | Option-Command-6 |
| Capture an area after 5 seconds | Shift-Option-Command-5 |
| Capture the full main display after 5 seconds | Shift-Option-Command-6 |

You can also trigger every action from the camera icon in the menu bar.

### Customize shortcuts

Open the camera menu and choose **Settings…** (or press **Command-,**). Click the shortcut beside any action, then press the new combination. iSnap saves custom shortcuts automatically and restores them the next time it launches. Duplicate combinations are rejected, and **Restore Defaults** returns all four actions to the original shortcuts.

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
- Persistent, customizable keyboard shortcuts
- Immediate lightweight preview
- Arrow, rectangle, and highlighter annotations
- Undo, redo, and clear annotation actions
- Copy, save, and close actions
- Local-only operation

## Enhanced editor (preview branch)

- Arrow, rectangle, highlight, freehand pen, oval, text labels, and solid black redaction.
- Six colors and three thicknesses. Highlight defaults to yellow; color and size preferences persist.
- Hold Shift while drawing to snap arrow angles or draw squares/circles.
- Undo/redo includes Clear. Escape cancels an unfinished stroke before closing the window.
- Fit, 100%, and zoom controls with scrolling for large screenshots.
- Copy & Close for the fast capture → annotate → paste workflow.
- Source pixel dimensions are preserved in PNG/clipboard exports, including Retina images.
- Existing annotations keep the same exported geometry and thickness after zooming/resizing.
- Canceling a new capture restores the previous editor and its annotations.

| Editor action | Shortcut |
| --- | --- |
| Arrow / Rectangle / Highlight | A / R / H |
| Pen / Oval / Text / Redact | P / O / T / X |
| Copy | Command-C or Return |
| Copy & Close | Shift-Command-C |
| Save PNG | Command-S |
| Undo / Redo | Command-Z / Shift-Command-Z |
| Fit / 100% | Command-0 / Command-1 |
| Zoom in / out | Command-Plus / Command-Minus |
| Close / Cancel unfinished stroke | Escape |
| Close | Command-W |

Text is added through a small input sheet after clicking the image. Color and thickness
apply to new annotations. Redaction is an opaque black fill baked into copied/saved
pixels; the unedited screenshot remains in memory while editing and on the clipboard
until you explicitly Copy the edited result. There is no automatic saving or history on disk.

### Validation

CI builds the app and runs native AppKit regression checks for Retina pixel dimensions,
opaque redaction, export invariance after zoom/resize, drawing tools, undo/redo/Clear,
cancelled strokes, clipboard shortcuts, and minimum/large preview layouts. It also
uploads preview snapshots. Hands-on multi-display capture, permission prompts, and
interactive save/text sheets still need testing on a Mac.
