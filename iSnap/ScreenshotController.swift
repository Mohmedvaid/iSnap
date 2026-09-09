import AppKit

final class ScreenshotController {
    private var previewWindowController: PreviewWindowController?
    private var isCapturing = false

    func capture(_ mode: CaptureMode, delay: TimeInterval = 0) {
        guard !isCapturing else {
            NSSound.beep()
            return
        }

        isCapturing = true
        // Hide the editor during capture, but keep its edits if selection is cancelled.
        guard previewWindowController?.window?.attachedSheet == nil else {
            isCapturing = false
            NSSound.beep()
            return
        }
        previewWindowController?.window?.orderOut(nil)

        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ScreenshotCommandBuilder.arguments(for: mode, delay: delay)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try process.run()
                process.waitUntilExit()

                DispatchQueue.main.async {
                    self?.captureDidFinish(
                        process: process,
                        previousPasteboardChangeCount: previousChangeCount
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isCapturing = false
                    self?.restorePreview()
                    self?.showCaptureError(error)
                }
            }
        }
    }

    private func captureDidFinish(
        process: Process,
        previousPasteboardChangeCount: Int
    ) {
        isCapturing = false

        let pasteboard = NSPasteboard.general
        guard process.terminationStatus == 0,
              pasteboard.changeCount != previousPasteboardChangeCount,
              let image = pasteboard.readObjects(
                  forClasses: [NSImage.self],
                  options: nil
              )?.first as? NSImage else {
            restorePreview()
            return
        }

        previewWindowController?.close()
        let preview = PreviewWindowController(image: image)
        preview.onClose = { [weak self, weak preview] in
            if self?.previewWindowController === preview {
                self?.previewWindowController = nil
            }
        }
        previewWindowController = preview

        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        preview.showWindow(nil)
        preview.window?.makeKeyAndOrderFront(nil)
    }

    private func restorePreview() {
        guard let preview = previewWindowController else { return }
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        preview.showWindow(nil)
        preview.window?.makeKeyAndOrderFront(nil)
    }

    private func showCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "iSnap couldn't take the screenshot"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

