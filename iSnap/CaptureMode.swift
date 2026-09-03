import Foundation

enum CaptureMode {
    case area
    case fullScreen

    var displayName: String {
        switch self {
        case .area:
            return "Area"
        case .fullScreen:
            return "Full Screen"
        }
    }
}

enum ScreenshotCommandBuilder {
    static func arguments(for mode: CaptureMode, delay: TimeInterval) -> [String] {
        var arguments: [String]

        switch mode {
        case .area:
            arguments = ["-i", "-c", "-x"]
        case .fullScreen:
            arguments = ["-m", "-c", "-x"]
        }

        if delay > 0 {
            arguments.append(contentsOf: ["-T", String(Int(delay))])
        }

        return arguments
    }
}

