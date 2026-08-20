import Foundation

public struct ImpactEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let time: TimeInterval
    public let score: Double
    public let amplitude: Double
    public let midEnergyRatio: Double
    public let highEnergyRatio: Double

    public init(
        id: UUID = UUID(),
        time: TimeInterval,
        score: Double,
        amplitude: Double,
        midEnergyRatio: Double,
        highEnergyRatio: Double
    ) {
        self.id = id
        self.time = time
        self.score = score
        self.amplitude = amplitude
        self.midEnergyRatio = midEnergyRatio
        self.highEnergyRatio = highEnergyRatio
    }
}

public struct ClipRange: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let start: TimeInterval
    public let end: TimeInterval

    public var duration: TimeInterval { end - start }

    public init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval) {
        self.id = id
        self.start = start
        self.end = end
    }
}

public struct TrainingSession: Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let sourceURL: URL
    public let outputURL: URL
    public let impacts: [ImpactEvent]
    public let clips: [ClipRange]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceURL: URL,
        outputURL: URL,
        impacts: [ImpactEvent],
        clips: [ClipRange]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.impacts = impacts
        self.clips = clips
    }

    public var compiledDuration: TimeInterval {
        clips.reduce(0) { $0 + $1.duration }
    }
}

public enum ProcessingStage: String, Sendable {
    case preparing
    case readingAudio
    case findingImpacts
    case assemblingRallies
    case exporting

    public var title: String {
        switch self {
        case .preparing: "Preparando o treino"
        case .readingAudio: "Lendo o áudio"
        case .findingImpacts: "Encontrando batidas"
        case .assemblingRallies: "Montando as jogadas"
        case .exporting: "Exportando o vídeo"
        }
    }
}

public struct ProcessingUpdate: Sendable {
    public let stage: ProcessingStage
    public let fraction: Double

    public init(stage: ProcessingStage, fraction: Double) {
        self.stage = stage
        self.fraction = min(max(fraction, 0), 1)
    }
}
