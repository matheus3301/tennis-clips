import SwiftData
import SwiftUI

struct CompletedSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    @State private var isPresentingFullScreen = false
    let session: TennisSession

    var body: some View {
        GeometryReader { proxy in
            if let outputURL = model.outputURL(for: session) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("VÍDEO PRONTO")
                        .font(.caption.weight(.black))
                        .tracking(1.7)
                        .foregroundStyle(AppPalette.clayMark)
                    Text("As jogadas que você escolheu.")
                        .displayType(size: 32)
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                    SessionMetadataSummary(session: session, compact: true)
                    FinalVideoPlayer(url: outputURL)
                        .frame(height: playerHeight(for: proxy.size.height))
                        .clipShape(.rect(cornerRadius: 22))
                        .overlay(alignment: .topTrailing) {
                            Button(
                                "Ver em tela cheia",
                                systemImage: "arrow.up.left.and.arrow.down.right",
                                action: presentFullScreen
                            )
                            .buttonStyle(.plain)
                            .labelStyle(.iconOnly)
                            .font(.title3.bold())
                            .foregroundStyle(.black)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.9), in: .circle)
                            .overlay {
                                Circle()
                                    .stroke(.black.opacity(0.12), lineWidth: 1)
                            }
                            .padding(10)
                        }
                    HStack(spacing: 9) {
                        SummaryMetric(value: String(session.keptClips.count), label: "jogadas")
                        SummaryMetric(value: session.compiledDuration.shortDuration, label: "duração")
                    }
                    HStack(spacing: 9) {
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
                    HStack(spacing: 9) {
                        NavigationLink(value: AppRoute.montage(session.id)) {
                            Label("Rever cortes", systemImage: "rectangle.grid.2x2")
                        }
                        .buttonStyle(QuietActionButtonStyle())
                        Button {
                            model.compile(session, context: modelContext)
                        } label: {
                            Label("Remontar", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .fullScreenCover(isPresented: $isPresentingFullScreen) {
                    FullScreenVideoPlayer(url: outputURL)
                }
            }
        }
    }

    private func playerHeight(for availableHeight: CGFloat) -> CGFloat {
        let titleStatusAllowance: CGFloat = session.titleOrigin == .automatic
            && session.automaticTitleState != .generated ? 72 : 0
        return min(max(availableHeight * 0.35 - titleStatusAllowance, 128), 260)
    }

    private func presentFullScreen() {
        isPresentingFullScreen = true
    }
}

struct FailureSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    let session: TennisSession

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "waveform.badge.exclamationmark").font(.system(size: 54, weight: .bold)).foregroundStyle(AppPalette.clayMark)
            Text("Não conseguimos separar as jogadas.").displayType(size: 33).multilineTextAlignment(.center).foregroundStyle(AppPalette.ink)
            Text(session.errorMessage ?? "Confira as gravações e tente novamente.").multilineTextAlignment(.center).foregroundStyle(AppPalette.ink.opacity(0.6))
            SessionMetadataSummary(session: session)
            Button(action: retry) {
                Label("Tentar novamente", systemImage: "arrow.clockwise")
            }
                .buttonStyle(PrimaryActionButtonStyle())
            Spacer()
        }
        .padding(26)
    }

    private func retry() {
        if !session.keptClips.isEmpty, session.pendingClipCount == 0 {
            model.compile(session, context: modelContext)
        } else {
            model.startAnalysis(session, context: modelContext)
        }
    }
}
