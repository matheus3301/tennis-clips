import SwiftData
import SwiftUI

private enum AppSheet: String, Identifiable {
    case newSession
    case settings
    var id: String { rawValue }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TennisSession.playedAt, order: .reverse) private var sessions: [TennisSession]
    private let startupIssue: String?

    @State private var intentRouter = AppIntentRouter.shared
    @State private var path: [AppRoute] = []
    @State private var presentedSheet: AppSheet?
    @State private var isPresentingStartupIssue: Bool

    init(startupIssue: String? = nil) {
        self.startupIssue = startupIssue
        _isPresentingStartupIssue = State(initialValue: startupIssue != nil)
    }

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView(
                onCreate: { presentedSheet = .newSession },
                onSettings: { presentedSheet = .settings }
            )
            .navigationDestination(for: AppRoute.self) { route in
                SessionDestinationView(route: route)
            }
        }
        .tint(AppPalette.baseline)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .newSession:
                NewSessionView { sessionID in
                    path.append(.session(sessionID))
                }
            case .settings:
                SettingsView()
            }
        }
        .overlay(alignment: .top) {
            if let notice = model.notice {
                ToastView(notice: notice)
                    .padding(.top, 8)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                    .task(id: notice.id) {
                        try? await Task.sleep(for: .seconds(2.6))
                        guard model.notice?.id == notice.id else { return }
                        withAnimation { model.notice = nil }
                    }
            }
        }
        .animation(
            reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.35, dampingFraction: 0.82),
            value: model.notice
        )
        .onOpenURL(perform: openDeepLink)
        .task(id: intentRouter.request?.id) {
            handleIntentRequest()
        }
        .alert("Histórico indisponível", isPresented: $isPresentingStartupIssue) {
            Button("Continuar", role: .cancel) {}
        } message: {
            Text(startupIssue ?? "Tente abrir o app novamente.")
        }
    }

    private func openDeepLink(_ url: URL) {
        guard url.scheme == "tennisclips",
              url.host == "session",
              let sessionID = UUID(uuidString: url.lastPathComponent)
        else { return }
        presentedSheet = nil
        path = [.session(sessionID)]
    }

    private func handleIntentRequest() {
        guard let request = intentRouter.request else { return }
        defer { intentRouter.request = nil }
        switch request.destination {
        case .newSession:
            path = []
            presentedSheet = .newSession
        case .continueReview:
            guard let session = sessions.first(where: {
                $0.status == .reviewing || $0.status == .ready
            }) else {
                model.notice = .warning("Não há uma revisão pendente no momento.")
                return
            }
            presentedSheet = nil
            path = [
                session.pendingClipCount > 0
                    ? .review(session.id)
                    : .montage(session.id)
            ]
        case .session(let sessionID):
            presentedSheet = nil
            path = [.session(sessionID)]
        }
    }
}

private struct SessionDestinationView: View {
    @Query private var sessions: [TennisSession]
    private let route: AppRoute

    init(route: AppRoute) {
        self.route = route
        let sessionID = route.sessionID
        _sessions = Query(filter: #Predicate<TennisSession> { $0.id == sessionID })
    }

    var body: some View {
        if let session = sessions.first {
            switch route {
            case .session:
                SessionDetailView(session: session)
            case .review:
                RallyReviewView(session: session)
            case .montage:
                MontageEditorView(session: session)
            case .rally(_, let clipID):
                RallyDetailEditorView(session: session, initialClipID: clipID)
            }
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
    let notice: AppNotice

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if #available(iOS 26.0, *) {
            label
                .glassEffect(.regular.tint(tint), in: .capsule)
        } else {
            label
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var label: some View {
        Label(notice.message, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppPalette.chalk)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .environment(\.colorScheme, .dark)
            .shadow(color: AppPalette.ink.opacity(0.18), radius: 14, y: 7)
            .padding(.horizontal, 20)
    }

    private var tint: Color {
        switch notice.kind {
        case .success: AppPalette.baseline
        case .warning: AppPalette.clayMark
        case .error: .red
        }
    }

    private var symbol: String {
        switch notice.kind {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }
}
