import Foundation

nonisolated enum SessionTitleGenerationOutcome: Sendable, Equatable {
    case generated(String)
    case unavailable(AutomaticTitleState)
    case failed
}
