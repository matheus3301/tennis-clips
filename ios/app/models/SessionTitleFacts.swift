import Foundation

nonisolated struct SessionTitleFacts: Sendable, Equatable {
    let kind: SessionKind
    let playedAt: Date
    let recordedDuration: TimeInterval
    let opponent: String
    let location: String?
    let recordingCount: Int
    let rallyCount: Int

    var periodOfDay: String {
        switch Calendar.current.component(.hour, from: playedAt) {
        case 5..<12: "pela manhã"
        case 12..<18: "à tarde"
        case 18..<24: "à noite"
        default: "de madrugada"
        }
    }
}
