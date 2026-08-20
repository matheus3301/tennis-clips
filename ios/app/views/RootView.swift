import SwiftUI
import TennisClipsCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AppPalette.chalk.ignoresSafeArea()
            switch model.phase {
            case .idle:
                HomeView()
            case .processing(let update):
                ProcessingView(update: update)
            case .completed(let session):
                ResultView(session: session)
            case .failed(let message):
                FailureView(message: message)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: phaseKey)
    }

    private var phaseKey: String {
        switch model.phase {
        case .idle: "idle"
        case .processing(let update): update.stage.rawValue
        case .completed: "completed"
        case .failed: "failed"
        }
    }
}
