import AppIntents
import Observation
import SwiftData

@MainActor
@Observable
final class AppIntentRouter {
    nonisolated enum Destination: Equatable, Sendable {
        case newSession
        case continueReview
        case session(UUID)
    }

    nonisolated struct Request: Equatable, Sendable {
        let id = UUID()
        let destination: Destination
    }

    static let shared = AppIntentRouter()
    var request: Request?

    private init() {}
}

nonisolated struct OpenNewSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir nova sessão"
    static let description = IntentDescription("Abre o Tennis Clips para escolher novas gravações.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentRouter.shared.request = .init(destination: .newSession)
        return .result()
    }
}

nonisolated struct ContinueReviewIntent: AppIntent {
    static let title: LocalizedStringResource = "Continuar revisão"
    static let description = IntentDescription("Abre a revisão de jogadas mais recente.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentRouter.shared.request = .init(destination: .continueReview)
        return .result()
    }
}

nonisolated struct TennisSessionEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sessão de tênis"
    static let defaultQuery = TennisSessionEntityQuery()

    let id: String
    let title: String
    let subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }
}

nonisolated struct TennisSessionEntityQuery: EntityQuery {
    func entities(for identifiers: [TennisSessionEntity.ID]) async throws -> [TennisSessionEntity] {
        try await fetchEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [TennisSessionEntity] {
        try await fetchEntities()
    }

    private func fetchEntities() async throws -> [TennisSessionEntity] {
        try await MainActor.run {
            let schema = Schema(versionedSchema: TennisClipsSchemaV1.self)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: TennisClipsMigrationPlan.self
            )
            var descriptor = FetchDescriptor<TennisSession>(
                sortBy: [SortDescriptor(\TennisSession.playedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 20
            return try container.mainContext.fetch(descriptor).map { session in
                TennisSessionEntity(
                    id: session.id.uuidString,
                    title: session.displayTitle,
                    subtitle: session.status.label
                )
            }
        }
    }
}

struct OpenSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir sessão"
    static let description = IntentDescription("Abre uma sessão específica no Tennis Clips.")
    static let openAppWhenRun = true

    @Parameter(title: "Sessão")
    var session: TennisSessionEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let sessionID = UUID(uuidString: session.id) else { return .result() }
        AppIntentRouter.shared.request = .init(destination: .session(sessionID))
        return .result()
    }
}

nonisolated struct TennisClipsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenNewSessionIntent(),
            phrases: ["Abrir nova sessão no \(.applicationName)"],
            shortTitle: "Nova sessão",
            systemImageName: "video.badge.plus"
        )
        AppShortcut(
            intent: ContinueReviewIntent(),
            phrases: ["Continuar revisão no \(.applicationName)"],
            shortTitle: "Continuar revisão",
            systemImageName: "rectangle.stack.fill"
        )
    }
}
