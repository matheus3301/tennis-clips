import SwiftUI
import SwiftData

@main
struct TennisClipsApp: App {
    @State private var model = AppModel()
    @AppStorage("appAppearance") private var appAppearanceRaw = AppAppearance.system.rawValue
    private let modelContainer: ModelContainer
    private let startupIssue: String?

    init() {
        let schema = Schema(versionedSchema: TennisClipsSchemaV1.self)
        do {
            modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: TennisClipsMigrationPlan.self
            )
            startupIssue = nil
        } catch {
            do {
                modelContainer = try ModelContainer(
                    for: schema,
                    migrationPlan: TennisClipsMigrationPlan.self,
                    configurations: ModelConfiguration(
                        schema: schema,
                        isStoredInMemoryOnly: true
                    )
                )
                startupIssue = "O histórico não pôde ser aberto. Seus vídeos continuam preservados no aparelho; esta sessão será temporária."
            } catch {
                fatalError("Não foi possível iniciar o armazenamento temporário: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(startupIssue: startupIssue)
                .environment(model)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .modelContainer(modelContainer)
    }

    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRaw) ?? .system
    }
}
