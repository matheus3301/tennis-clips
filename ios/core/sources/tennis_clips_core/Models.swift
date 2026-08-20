import Foundation

public struct ImpactEvent: Codable, Equatable, Sendable {
    public let time: TimeInterval
    public let score: Double
    public let amplitude: Double
    public let midEnergyRatio: Double
    public let highEnergyRatio: Double
    public let motionRatio: Double

    public init(
        time: TimeInterval,
        score: Double,
        amplitude: Double,
        midEnergyRatio: Double,
        highEnergyRatio: Double,
        motionRatio: Double = 0
    ) {
        self.time = time
        self.score = score
        self.amplitude = amplitude
        self.midEnergyRatio = midEnergyRatio
        self.highEnergyRatio = highEnergyRatio
        self.motionRatio = motionRatio
    }
}

public struct ClipRange: Codable, Equatable, Sendable {
    public let start: TimeInterval
    public let end: TimeInterval

    public var duration: TimeInterval { end - start }

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }
}

public struct TrainingSession: Sendable {
    public let outputURL: URL
    public let impacts: [ImpactEvent]
    public let clips: [ClipRange]

    public init(
        outputURL: URL,
        impacts: [ImpactEvent],
        clips: [ClipRange]
    ) {
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
