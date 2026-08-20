import AVKit
import SwiftUI
import TennisClipsCore

struct ResultView: View {
    @Environment(AppModel.self) private var model
    let session: TrainingSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("COMPILAÇÃO PRONTA")
                            .font(.caption.weight(.black))
                            .tracking(1.5)
                            .foregroundStyle(AppPalette.clay)
                        Text("Seu treino, sem espera.")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(AppPalette.ink)
                    }
                    Spacer()
                }

                VideoPlayer(player: AVPlayer(url: session.outputURL))
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                HStack(spacing: 12) {
                    MetricCard(value: "\(session.impacts.count)", label: "batidas")
                    MetricCard(value: "\(session.clips.count)", label: "jogadas")
                    MetricCard(value: session.compiledDuration.formattedDuration, label: "vídeo")
                }

                ShareLink(item: session.outputURL) {
                    Label("Compartilhar vídeo", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .foregroundStyle(AppPalette.chalk)
                        .background(AppPalette.court, in: RoundedRectangle(cornerRadius: 17))
                }

                Button("Processar outro treino") { model.startOver() }
                    .font(.headline)
                    .foregroundStyle(AppPalette.court)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
    }
}

private struct MetricCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 25, weight: .black, design: .rounded))
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppPalette.ink.opacity(0.56))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppPalette.line.opacity(0.52), in: RoundedRectangle(cornerRadius: 15))
        .foregroundStyle(AppPalette.ink)
    }
}

private extension TimeInterval {
    var formattedDuration: String {
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
