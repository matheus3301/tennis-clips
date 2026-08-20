import SwiftUI
import SwiftData

@main
struct TennisClipsApp: App {
    @State private var model = AppModel()
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(
                for: TennisSession.self,
                SessionVideo.self,
                RallyClip.self
            )
        } catch {
            fatalError("Não foi possível abrir o histórico: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)
    }
}
