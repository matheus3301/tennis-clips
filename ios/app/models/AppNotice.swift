import Foundation

nonisolated struct AppNotice: Equatable, Identifiable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case success
        case warning
        case error
    }

    let id = UUID()
    let kind: Kind
    let message: String

    static func success(_ message: String) -> AppNotice {
        AppNotice(kind: .success, message: message)
    }

    static func warning(_ message: String) -> AppNotice {
        AppNotice(kind: .warning, message: message)
    }

    static func error(_ message: String) -> AppNotice {
        AppNotice(kind: .error, message: message)
    }
}
