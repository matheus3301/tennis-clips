import Foundation

nonisolated enum AppRoute: Hashable {
    case session(UUID)
    case review(UUID)
    case montage(UUID)
    case rally(UUID, UUID)

    var sessionID: UUID {
        switch self {
        case .session(let id), .review(let id), .montage(let id): id
        case .rally(let sessionID, _): sessionID
        }
    }
}
