import Foundation
import TennisClipsCore

nonisolated struct VideoAnalysis: Sendable {
    let duration: TimeInterval
    let impacts: [ImpactEvent]
    let clips: [ClipRange]
}

nonisolated protocol TennisAnalyzing: Sendable {
    func analyze(
        videoAt url: URL,
        progress: @escaping @MainActor @Sendable (ProcessingUpdate) -> Void
    ) async throws -> VideoAnalysis
}

nonisolated enum ProcessingError: LocalizedError {
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
        case .noImpacts: "Nenhuma jogada foi encontrada. Confira se o áudio está audível e se a quadra aparece na gravação."
        case .cannotReadMedia: "Não foi possível ler o arquivo de vídeo."
        case .cannotCreateExport: "Não foi possível preparar a exportação."
        case .exportFailed(let error): "A exportação falhou: \(error?.localizedDescription ?? "erro desconhecido")."
        }
    }
}
