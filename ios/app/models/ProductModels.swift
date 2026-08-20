import Foundation
import SwiftData

nonisolated enum SessionKind: String, Codable, CaseIterable, Identifiable {
    case match
    case practice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .match: "Jogo"
        case .practice: "Treino"
        }
    }
}

nonisolated enum SessionStatus: String, Codable {
    case analyzing
    case reviewing
    case ready
    case exporting
    case completed
    case failed

    var label: String {
        switch self {
        case .analyzing: "Encontrando jogadas"
        case .reviewing: "Revisão pendente"
        case .ready: "Pronto para montar"
        case .exporting: "Montando vídeo"
        case .completed: "Concluído"
        case .failed: "Precisa de atenção"
        }
    }
}

nonisolated enum RallyDecision: String, Codable {
    case pending
    case kept
    case rejected
}

nonisolated enum SessionTitleOrigin: String, Codable {
    case automatic
    case manual
    case legacy
}

@Model
final class TennisSession {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var title: String
    var titleOriginRaw: String = SessionTitleOrigin.legacy.rawValue
    var opponent: String
    var playedAt: Date
    var playedAtIsManual: Bool = true
    var locationName: String?
    var locality: String?
    var latitude: Double?
    var longitude: Double?
    var metadataVersion: Int = 0
    var createdAt: Date
    var updatedAt: Date
    var statusRaw: String
    var progress: Double
    var progressLabel: String
    var outputPath: String?
    var errorMessage: String?

    @Relationship(deleteRule: .cascade)
    var videos: [SessionVideo]

    @Relationship(deleteRule: .cascade)
    var clips: [RallyClip]

    init(
        id: UUID = UUID(),
        kind: SessionKind,
        title: String,
        opponent: String = "",
        playedAt: Date,
        playedAtIsManual: Bool = true,
        titleOrigin: SessionTitleOrigin = .legacy,
        status: SessionStatus = .analyzing
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title
        self.titleOriginRaw = titleOrigin.rawValue
        self.opponent = opponent
        self.playedAt = playedAt
        self.playedAtIsManual = playedAtIsManual
        self.locationName = nil
        self.locality = nil
        self.latitude = nil
        self.longitude = nil
        self.metadataVersion = 0
        self.createdAt = .now
        self.updatedAt = .now
        self.statusRaw = status.rawValue
        self.progress = 0
        self.progressLabel = "Preparando gravações"
        self.outputPath = nil
        self.errorMessage = nil
        self.videos = []
        self.clips = []
    }

    var kind: SessionKind {
        get { SessionKind(rawValue: kindRaw) ?? .match }
        set { kindRaw = newValue.rawValue }
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .failed }
        set {
            statusRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var titleOrigin: SessionTitleOrigin {
        get { SessionTitleOrigin(rawValue: titleOriginRaw) ?? .legacy }
        set { titleOriginRaw = newValue.rawValue }
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.title : trimmed
    }

    var sortedVideos: [SessionVideo] {
        videos.sorted { $0.order < $1.order }
    }

    var sortedClips: [RallyClip] {
        clips.sorted { $0.order < $1.order }
    }

    var keptClips: [RallyClip] {
        sortedClips.filter { $0.decision == .kept }
    }

    var pendingClipCount: Int {
        clips.filter { $0.decision == .pending }.count
    }

    var reviewedClipCount: Int {
        clips.count - pendingClipCount
    }

    var compiledDuration: TimeInterval {
        keptClips.reduce(0) { $0 + $1.duration }
    }

    var recordedDuration: TimeInterval {
        videos.reduce(0) { $0 + $1.duration }
    }

    var displayLocation: String? {
        if let locationName, !locationName.isEmpty { return locationName }
        if let locality, !locality.isEmpty { return locality }
        return nil
    }
}

@Model
final class SessionVideo {
    @Attribute(.unique) var id: UUID
    var order: Int
    var originalName: String
    var relativePath: String
    var duration: TimeInterval
    var capturedAt: Date?
    var latitude: Double?
    var longitude: Double?

    init(
        id: UUID = UUID(),
        order: Int,
        originalName: String,
        relativePath: String,
        duration: TimeInterval = 0,
        capturedAt: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.order = order
        self.originalName = originalName
        self.relativePath = relativePath
        self.duration = duration
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
    }
}

@Model
final class RallyClip {
    @Attribute(.unique) var id: UUID
    var sourceVideoID: UUID
    var order: Int
    var start: TimeInterval
    var end: TimeInterval
    var impactCount: Int
    var confidence: Double
    var decisionRaw: String
    var savedToPhotos: Bool

    init(
        id: UUID = UUID(),
        sourceVideoID: UUID,
        order: Int,
        start: TimeInterval,
        end: TimeInterval,
        impactCount: Int,
        confidence: Double,
        decision: RallyDecision = .pending
    ) {
        self.id = id
        self.sourceVideoID = sourceVideoID
        self.order = order
        self.start = start
        self.end = end
        self.impactCount = impactCount
        self.confidence = confidence
        self.decisionRaw = decision.rawValue
        self.savedToPhotos = false
    }

    var duration: TimeInterval { end - start }

    var decision: RallyDecision {
        get { RallyDecision(rawValue: decisionRaw) ?? .pending }
        set { decisionRaw = newValue.rawValue }
    }
}
