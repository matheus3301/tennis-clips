import AVKit
import SwiftData
import SwiftUI

struct CompletedSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    let session: TennisSession

    var body: some View {
        ScrollView {
            if let outputURL = model.outputURL(for: session) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("VÍDEO PRONTO").font(.caption.weight(.black)).tracking(1.7).foregroundStyle(AppPalette.clayMark)
                    Text("As jogadas que você escolheu.").displayType(size: 32).foregroundStyle(AppPalette.ink)
                    FinalVideoPlayer(url: outputURL)
                        .frame(height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    HStack(spacing: 10) {
                        SummaryMetric(value: String(session.keptClips.count), label: "jogadas")
                        SummaryMetric(value: session.compiledDuration.shortDuration, label: "duração")
                    }
                    HStack(spacing: 10) {
                        Button { Task { await model.saveCompilation(session) } } label: { Label("Salvar", systemImage: "square.and.arrow.down") }
                            .buttonStyle(PrimaryActionButtonStyle())
                        ShareLink(item: outputURL) { Label("Compartilhar", systemImage: "square.and.arrow.up") }
                            .buttonStyle(QuietActionButtonStyle())
                    }
                    NavigationLink(value: AppRoute.montage(session.id)) { Label("Rever jogadas e cortes", systemImage: "rectangle.grid.2x2") }
                        .buttonStyle(QuietActionButtonStyle())
                    Button { model.compile(session, context: modelContext) } label: { Label("Montar novamente", systemImage: "arrow.clockwise") }
                        .buttonStyle(PrimaryActionButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
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
            if isPlaying { AspectFillPlayerView(player: player).transition(.opacity) } else { VideoThumbnailView(url: url) }
            Button {
                isPlaying.toggle()
                isPlaying ? player.play() : player.pause()
            } label: {
                ZStack {
                    Color.clear
                    if !isPlaying {
                        Circle().fill(.ultraThinMaterial).frame(width: 72, height: 72)
                        Image(systemName: "play.fill").font(.title2.weight(.bold)).foregroundStyle(AppPalette.chalk)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pausar vídeo" : "Reproduzir vídeo")
        }
        .background(AppPalette.hardCourt)
        .animation(.easeOut(duration: 0.2), value: isPlaying)
        .onDisappear { player.pause(); isPlaying = false }
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

extension TimeInterval {
    var shortDuration: String {
        let total = Int(max(self, 0).rounded())
        let seconds = String(total % 60).leftPadded(to: 2, with: "0")
        return "\(total / 60):\(seconds)"
    }
}

private extension String {
    func leftPadded(to length: Int, with character: Character) -> String {
        String(repeating: character, count: max(0, length - count)) + self
    }
}
