import Foundation

nonisolated enum TitleStyle: String, CaseIterable, Identifiable, Sendable {
    case standard
    case creative

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Padrão"
        case .creative: "Criativo"
        }
    }

    var description: String {
        switch self {
        case .standard:
            "Cria títulos curtos e factuais usando data, horário, duração e local."
        case .creative:
            "Usa também as jogadas encontradas para criar títulos mais variados, sempre no aparelho."
        }
    }

    static var current: TitleStyle {
        let storedValue = UserDefaults.standard.string(forKey: "titleStyle")
        return storedValue.flatMap(TitleStyle.init(rawValue:)) ?? .standard
    }
}
