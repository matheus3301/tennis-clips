import SwiftData

nonisolated enum TennisClipsSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [TennisSession.self, SessionVideo.self, RallyClip.self]
    }
}

nonisolated enum TennisClipsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TennisClipsSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
