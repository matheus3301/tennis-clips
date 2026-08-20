import AVKit
import SwiftData
import SwiftUI

struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    let session: TennisSession

    var body: some View {
        ZStack {
            AppPalette.chalk.ignoresSafeArea()
            content
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
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

private struct ProcessingSessionView: View {
    let session: TennisSession

    var body: some View {
        VStack(spacing: 0) {
            ProcessingMessageRotator(messages: messages)
                .padding(.top, 32)
                .padding(.horizontal, 24)
                .zIndex(1)

            ProcessingAnimation()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .zIndex(0)

            VStack(alignment: .trailing, spacing: 8) {
                Text(session.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())

                ProgressView(value: session.progress)
                    .tint(AppPalette.ball)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    private var messages: [String] {
        if session.status == .exporting {
            return [
                "Reunindo suas jogadas favoritas.",
                "Ajustando cada corte.",
                "Colocando tudo na ordem.",
                "Finalizando seu vídeo.",
                "Preparando para salvar e compartilhar."
            ]
        }

        return [
            "Procurando as melhores jogadas.",
            "Detectando cada batida.",
            "Separando os melhores cortes.",
            "Organizando tudo para sua revisão.",
            "Deixando cada jogada pronta para você."
        ]
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

                RallyRail(
                    decisions: session.sortedClips.map(\.decision),
                    currentIndex: session.sortedClips.firstIndex { $0.decision == .pending }
                )

                NavigationLink {
                    RallyReviewView(session: session)
                } label: {
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

                NavigationLink {
                    RallyReviewView(session: session)
                } label: {
                    Label("Rever escolhas", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(QuietActionButtonStyle())

                Button {
                    model.compile(session, context: modelContext)
                } label: {
                    Label("Montar meu vídeo", systemImage: "play.rectangle.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
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

private struct SummaryMetric: View {
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

private struct CompletedSessionView: View {
    @Environment(AppModel.self) private var model
    let session: TennisSession

    var body: some View {
        GeometryReader { geometry in
            if let outputURL = model.outputURL(for: session) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VÍDEO PRONTO")
                            .font(.caption.weight(.black))
                            .tracking(1.7)
                            .foregroundStyle(AppPalette.clayMark)
                        Text("As jogadas que você escolheu.")
                            .displayType(size: 32)
                            .foregroundStyle(AppPalette.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.86)
                    }

                    FinalVideoPlayer(url: outputURL)
                        .frame(height: playerHeight(for: geometry.size.height))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    HStack(spacing: 10) {
                        SummaryMetric(value: String(session.keptClips.count), label: "jogadas")
                        SummaryMetric(value: session.compiledDuration.shortDuration, label: "duração")
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task { await model.saveCompilation(session) }
                        } label: {
                            Label("Salvar", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(PrimaryActionButtonStyle())

                        ShareLink(item: outputURL) {
                            Label("Compartilhar", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(QuietActionButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
        }
    }

    private func playerHeight(for availableHeight: CGFloat) -> CGFloat {
        min(430, max(238, availableHeight - 250))
    }
}

private struct FinalVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer
    @State private var isPlaying = false

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack {
            if isPlaying {
                AspectFillPlayerView(player: player)
                    .transition(.opacity)
            } else {
                VideoThumbnailView(url: url)
            }

            Button {
                isPlaying.toggle()
                isPlaying ? player.play() : player.pause()
            } label: {
                ZStack {
                    Color.clear
                    if !isPlaying {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 72, height: 72)
                        Image(systemName: "play.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppPalette.chalk)
                            .offset(x: 2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pausar vídeo" : "Reproduzir vídeo")
        }
        .background(AppPalette.hardCourt)
        .animation(.easeOut(duration: 0.2), value: isPlaying)
        .onDisappear {
            player.pause()
            isPlaying = false
        }
    }
}

private struct FailureSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    let session: TennisSession

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(AppPalette.clayMark)
            Text("Não conseguimos separar as jogadas.")
                .displayType(size: 33)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppPalette.ink)
            Text(session.errorMessage ?? "Confira as gravações e tente novamente.")
                .multilineTextAlignment(.center)
                .foregroundStyle(AppPalette.ink.opacity(0.6))

            Button {
                model.startAnalysis(session, context: modelContext)
            } label: {
                Label("Tentar novamente", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .padding(.top, 8)
            Spacer()
        }
        .padding(26)
    }
}

extension TimeInterval {
    var shortDuration: String {
        let total = Int(max(self, 0).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
