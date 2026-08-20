import Foundation

nonisolated enum AppCopy {
    static func plays(_ count: Int) -> String {
        count == 1 ? "1 jogada" : "\(count) jogadas"
    }

    static func reviewedPlays(_ reviewed: Int, total: Int) -> String {
        total == 1
            ? "\(reviewed) de 1 jogada revisada"
            : "\(reviewed) de \(total) jogadas revisadas"
    }

    static func importedRecordings(_ count: Int) -> String {
        count == 1 ? "Uma gravação importada" : "\(count) gravações importadas"
    }
}
