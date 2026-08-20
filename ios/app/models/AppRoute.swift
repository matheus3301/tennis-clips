import Foundation

nonisolated enum AppRoute: Hashable {
    case session(UUID)
    case review(UUID)

    var sessionID: UUID {
        switch self {
        case .session(let id), .review(let id): id
        }
    }
}
