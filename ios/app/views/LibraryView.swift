import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TennisSession.playedAt, order: .reverse) private var sessions: [TennisSession]

    let onCreate: () -> Void

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
            ToolbarItem(placement: .topBarTrailing) {
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
                    Text("Seus jogos e treinos, em ordem de quadra.")
                        .foregroundStyle(AppPalette.ink.opacity(0.58))
                }
                .padding(.bottom, 10)

                ForEach(sessions) { session in
                    NavigationLink(value: session.id) {
                        SessionCard(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 36)
        }
        .navigationTitle("Histórico")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SessionCard: View {
    @Environment(AppModel.self) private var model
    let session: TennisSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VideoThumbnailView(
                url: model.coverURL(for: session),
                time: session.sortedClips.first?.start ?? 0
            )
            .frame(height: 178)
            .clipped()
            .overlay(alignment: .topLeading) {
                Text(session.kind.title.uppercased())
                    .font(.caption2.weight(.black))
                    .tracking(1.3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .foregroundStyle(AppPalette.baseline)
                    .background(AppPalette.ball, in: Capsule())
                    .padding(14)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.displayTitle)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppPalette.ink)
                        Text(session.playedAt, format: .dateTime.day().month(.wide).year())
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.ink.opacity(0.55))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppPalette.ink.opacity(0.28))
                }

                RallyRail(
                    decisions: session.sortedClips.map(\.decision),
                    currentIndex: nil
                )

                HStack {
                    Label(session.status.label, systemImage: statusIcon)
                    Spacer()
                    if !session.clips.isEmpty {
                        Text(String(session.clips.count) + " jogadas")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.ink.opacity(0.56))
            }
            .padding(16)
            .background(AppPalette.courtMist)
        }
        .background(AppPalette.courtMist)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppPalette.baseline.opacity(0.07), lineWidth: 1)
        }
    }

    private var statusIcon: String {
        switch session.status {
        case .analyzing, .exporting: "circle.dotted"
        case .reviewing: "rectangle.stack"
        case .ready: "checkmark.circle"
        case .completed: "play.rectangle.fill"
        case .failed: "exclamationmark.triangle"
        }
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
