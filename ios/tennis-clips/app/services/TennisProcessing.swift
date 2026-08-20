import Foundation
import TennisClipsCore

protocol TennisProcessing: Sendable {
    func process(
        videoAt url: URL,
        progress: @escaping @MainActor @Sendable (ProcessingUpdate) -> Void
    ) async throws -> TrainingSession
}

enum ProcessingError: LocalizedError {
    case noAudio
    case noVideo
    case noImpacts
    case cannotReadMedia
    case cannotCreateExport
    case exportFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .noAudio: "O vídeo não tem uma faixa de áudio utilizável."
        case .noVideo: "O arquivo escolhido não tem uma faixa de vídeo."
        case .noImpacts: "Nenhuma batida passou pelos filtros deste treino."
        case .cannotReadMedia: "Não foi possível ler o arquivo de vídeo."
        case .cannotCreateExport: "Não foi possível preparar a exportação."
        case .exportFailed(let error): "A exportação falhou: \(error?.localizedDescription ?? "erro desconhecido")."
        }
    }
}
