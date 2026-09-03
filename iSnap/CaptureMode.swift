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
    static func arguments(for mode: CaptureMode, selectionRect: CGRect? = nil) -> [String] {
        switch mode {
        case .area:
            guard let rect = selectionRect?.standardized.integral else {
                return ["-i", "-c", "-x"]
            }
            let region = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
            return ["-R\(region)", "-c", "-x"]
        case .fullScreen:
            return ["-m", "-c", "-x"]
        }
    }
}
