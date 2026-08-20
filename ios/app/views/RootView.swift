import SwiftData
import SwiftUI

private enum AppSheet: String, Identifiable {
    case newSession
    var id: String { rawValue }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [UUID] = []
    @State private var presentedSheet: AppSheet?

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView {
                presentedSheet = .newSession
            }
            .navigationDestination(for: UUID.self) { sessionID in
                SessionDestinationView(sessionID: sessionID)
            }
        }
        .tint(AppPalette.baseline)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .newSession:
                NewSessionView { sessionID in
                    path.append(sessionID)
                }
            }
        }
        .overlay(alignment: .top) {
            if let message = model.toastMessage {
                ToastView(message: message)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.6))
                        guard model.toastMessage == message else { return }
                        withAnimation { model.toastMessage = nil }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: model.toastMessage)
    }
}

private struct SessionDestinationView: View {
    @Query private var sessions: [TennisSession]

    init(sessionID: UUID) {
        _sessions = Query(filter: #Predicate<TennisSession> { $0.id == sessionID })
    }

    var body: some View {
        if let session = sessions.first {
            SessionDetailView(session: session)
        } else {
            ContentUnavailableView(
                "Sessão não encontrada",
                systemImage: "rectangle.slash",
                description: Text("Ela pode ter sido removida do histórico.")
            )
        }
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppPalette.chalk)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
            .shadow(color: AppPalette.ink.opacity(0.18), radius: 14, y: 7)
            .padding(.horizontal, 20)
    }
}
