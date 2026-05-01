import SwiftUI

struct StatusValue {
    let text: String
    let level: StatusLevel
}

enum StatusLevel {
    case success
    case warning
    case error
    case info

    var color: Color {
        switch self {
        case .success:
            return Color.green
        case .warning:
            return Color.orange
        case .error:
            return Color.red
        case .info:
            return Color.accentColor
        }
    }
}

enum OptionAsAltStatus: Equatable {
    case unknown
    case enabled
    case disabled
    case inProgress(String)
    case error(String)

    var isEnabled: Bool {
        if case .enabled = self { return true }
        return false
    }

    var isDisabled: Bool {
        if case .disabled = self { return true }
        return false
    }
}

struct PatchFeedback: Equatable {
    let title: String
    let message: String
    let isError: Bool
}
