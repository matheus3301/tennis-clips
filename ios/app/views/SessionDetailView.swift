import AVKit
import SwiftData
import SwiftUI

struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    let session: TennisSession
    @State private var isEditing = false

    var body: some View {
        ZStack {
            AppPalette.chalk.ignoresSafeArea()
            content
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            SessionMetadataSummary(session: session)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Editar", systemImage: "pencil") {
                    isEditing = true
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditSessionView(session: session)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.status {
        case .analyzing, .exporting:
            ProcessingSessionView(session: session)
        case .reviewing:
            ReviewReadyView(session: session)
        case .ready:
            ReviewSummaryView(session: session)
        case .completed:
            CompletedSessionView(session: session)
        case .failed:
            FailureSessionView(session: session)
        }
    }
}

private struct ReviewReadyView: View {
    @Environment(AppModel.self) private var model
    let session: TennisSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VideoThumbnailView(
                    url: model.coverURL(for: session),
                    time: session.sortedClips.first?.start ?? 0
                )
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Text(String(session.clips.count))
                        .displayType(size: 52)
                        .foregroundStyle(AppPalette.baseline)
                        .frame(width: 88, height: 88)
                        .background(AppPalette.ball, in: Circle())
                        .padding(18)
                        .accessibilityLabel(String(session.clips.count) + " jogadas")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(session.reviewedClipCount == 0 ? "Suas jogadas estão prontas." : "Continue de onde parou.")
                        .displayType(size: 34)
                        .foregroundStyle(AppPalette.ink)
                    Text("Veja uma por uma. Inclua o que entra no vídeo ou descarte o que não precisa ficar.")
                        .foregroundStyle(AppPalette.ink.opacity(0.62))
                        .lineSpacing(3)
                }

                if let message = session.errorMessage {
                    PartialAnalysisNotice(message: message)
                }

                RallyRail(
                    decisions: session.sortedClips.map(\.decision),
                    currentIndex: session.sortedClips.firstIndex { $0.decision == .pending }
                )

                NavigationLink(value: AppRoute.review(session.id)) {
                    Label(
                        session.reviewedClipCount == 0 ? "Revisar jogadas" : "Continuar revisão",
                        systemImage: "rectangle.stack.fill"
                    )
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
            .padding(20)
            .padding(.bottom, 28)
        }
    }
}

private struct ReviewSummaryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    let session: TennisSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Revisão concluída")
                    .font(.caption.weight(.black))
                    .tracking(1.7)
                    .foregroundStyle(AppPalette.hardCourt)

                Text(summaryTitle)
                    .displayType(size: 42)
                    .foregroundStyle(AppPalette.ink)

                if let message = session.errorMessage {
                    PartialAnalysisNotice(message: message)
                }

                HStack(spacing: 10) {
                    SummaryMetric(value: String(session.keptClips.count), label: "incluídas")
                    SummaryMetric(
                        value: String(session.clips.count - session.keptClips.count),
                        label: "descartadas"
                    )
                    SummaryMetric(value: session.compiledDuration.shortDuration, label: "de vídeo")
                }

                RallyRail(decisions: session.sortedClips.map(\.decision), currentIndex: nil)
                    .padding(.vertical, 8)

                NavigationLink(value: AppRoute.montage(session.id)) {
                    Label("Rever escolhas", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(QuietActionButtonStyle())

                Button {
                    model.compile(session, context: modelContext)
                } label: {
                    Label("Montar meu vídeo", systemImage: "play.rectangle.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(session.keptClips.isEmpty)
                .opacity(session.keptClips.isEmpty ? 0.48 : 1)

                if session.keptClips.isEmpty {
                    Label(
                        "Inclua pelo menos uma jogada para montar o vídeo.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(AppPalette.ink.opacity(0.62))
                }
            }
            .padding(20)
            .padding(.top, 18)
        }
    }

    private var summaryTitle: String {
        if session.keptClips.count == 1 { return "Uma jogada vai para o vídeo." }
        return String(session.keptClips.count) + " jogadas vão para o vídeo."
    }
}

private struct PartialAnalysisNotice: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(AppPalette.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.ball.opacity(0.24), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
    }
}

struct SummaryMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .displayType(size: 29)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppPalette.courtMist.opacity(0.52), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(AppPalette.ink)
    }
}
