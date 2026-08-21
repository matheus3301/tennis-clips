import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TennisSession.playedAt, order: .reverse) private var sessions: [TennisSession]
    @State private var sessionPendingDeletion: TennisSession?
    @State private var searchText = ""
    @State private var selectedFilter: LibraryFilter = .all

    let onCreate: () -> Void
    let onSettings: () -> Void

    var body: some View {
        ZStack {
            AppPalette.chalk.ignoresSafeArea()
            if sessions.isEmpty {
                emptyState
            } else {
                history
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !sessions.isEmpty {
                    Menu {
                        Picker("Filtrar histórico", selection: $selectedFilter) {
                            ForEach(LibraryFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                    } label: {
                        Image(systemName: selectedFilter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filtrar histórico")
                }

                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Ajustes")

                Button(action: onCreate) {
                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                }
                .accessibilityLabel("Adicionar jogo ou treino")
            }
        }
        .task {
            model.resumeIfNeeded(sessions, context: modelContext)
        }
        .searchable(text: $searchText, prompt: "Buscar sessões")
        .confirmationDialog(
            "Remover esta sessão?",
            isPresented: deletionBinding,
            titleVisibility: .visible
        ) {
            Button("Remover sessão", role: .destructive, action: deletePendingSession)
            Button("Cancelar", role: .cancel) { sessionPendingDeletion = nil }
        } message: {
            Text("As gravações, jogadas e compilações desta sessão serão apagadas do app.")
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("TENNIS CLIPS")
                    .font(.caption.weight(.black))
                    .tracking(2.2)
                    .foregroundStyle(AppPalette.hardCourt)
                    .padding(.top, 18)

                Spacer(minLength: 70)

                ZStack {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(AppPalette.hardCourt)
                    CourtGlyph()
                        .stroke(AppPalette.chalk.opacity(0.72), lineWidth: 2)
                        .padding(32)
                    Circle()
                        .fill(AppPalette.ball)
                        .frame(width: 28, height: 28)
                        .offset(x: 86, y: -42)
                        .shadow(color: AppPalette.ball.opacity(0.38), radius: 12)
                }
                .frame(height: 224)

                Text("O jogo termina.\nAs jogadas ficam.")
                    .displayType(size: 44)
                    .tracking(-1.4)
                    .foregroundStyle(AppPalette.ink)
                    .padding(.top, 32)

                Text("Adicione suas gravações, escolha o que vale guardar e monte um vídeo só com as suas jogadas.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppPalette.ink.opacity(0.66))
                    .lineSpacing(4)
                    .padding(.top, 14)

                Button(action: onCreate) {
                    Label("Adicionar jogo ou treino", systemImage: "plus")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .padding(.top, 28)

                Label("Seus vídeos não saem do iPhone", systemImage: "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppPalette.ink.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .navigationBarHidden(true)
    }

    private var history: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TENNIS CLIPS")
                        .font(.caption.weight(.black))
                        .tracking(2.2)
                        .foregroundStyle(AppPalette.hardCourt)
                    Text("Histórico")
                        .displayType(size: 42)
                        .foregroundStyle(AppPalette.ink)
                    Text("Seus jogos e treinos, do mais recente ao mais antigo.")
                        .foregroundStyle(AppPalette.ink.opacity(0.58))
                }
                .padding(.bottom, 10)

                if filteredSessions.isEmpty {
                    ContentUnavailableView.search
                        .frame(maxWidth: .infinity)
                        .padding(.top, 50)
                } else {
                    ForEach(filteredSessions) { session in
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .topTrailing) {
                                NavigationLink(value: AppRoute.session(session.id)) {
                                    SessionCard(session: session)
                                }
                                .buttonStyle(.plain)

                                Menu {
                                    Button("Remover sessão", systemImage: "trash", role: .destructive) {
                                        sessionPendingDeletion = session
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(AppPalette.chalk)
                                        .frame(width: 44, height: 44)
                                        .background(.ultraThinMaterial, in: Circle())
                                        .environment(\.colorScheme, .dark)
                                }
                                .padding(10)
                                .accessibilityLabel("Mais opções para \(session.displayTitle)")
                            }

                            if session.status == .reviewing {
                                NavigationLink(value: AppRoute.review(session.id)) {
                                    Label("Continuar revisão", systemImage: "rectangle.stack.fill")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppPalette.baseline)
                                .padding(.horizontal, 8)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 36)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filteredSessions: [TennisSession] {
        sessions.filter { session in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all: matchesFilter = true
            case .matches: matchesFilter = session.kind == .match
            case .practices: matchesFilter = session.kind == .practice
            case .pending: matchesFilter = session.status == .reviewing || session.status == .ready
            case .completed: matchesFilter = session.status == .completed
            }
            guard matchesFilter else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return session.matchesSearch(query)
        }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { sessionPendingDeletion != nil },
            set: { if !$0 { sessionPendingDeletion = nil } }
        )
    }

    private func deletePendingSession() {
        guard let sessionPendingDeletion else { return }
        model.delete(sessionPendingDeletion, context: modelContext)
        self.sessionPendingDeletion = nil
    }
}

#Preview("Histórico vazio") {
    RootView()
        .environment(AppModel())
        .modelContainer(
            for: [TennisSession.self, SessionVideo.self, RallyClip.self],
            inMemory: true
        )
}
