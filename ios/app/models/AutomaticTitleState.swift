import Foundation

nonisolated enum AutomaticTitleState: String, Codable, Sendable {
    case legacy
    case notApplicable
    case pending
    case generating
    case generated
    case unsupportedOS
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedLanguage
    case failed

    var canRetry: Bool {
        switch self {
        case .appleIntelligenceNotEnabled, .modelNotReady, .unsupportedLanguage, .failed:
            true
        case .legacy, .notApplicable, .pending, .generating, .generated,
             .unsupportedOS, .deviceNotEligible:
            false
        }
    }
}
