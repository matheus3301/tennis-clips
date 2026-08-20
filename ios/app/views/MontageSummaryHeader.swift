import SwiftUI

struct MontageSummaryHeader: View {
    let includedCount: Int
    let rejectedCount: Int
    let duration: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MONTAGEM")
                .font(.caption.bold())
                .tracking(1.7)
                .foregroundStyle(AppPalette.hardCourt)

            Text(title)
                .displayType(size: 40)
                .foregroundStyle(AppPalette.ink)

            Text("Veja o conjunto, compare as escolhas e abra somente o que quiser ajustar.")
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    metrics
                }

                VStack(spacing: 10) {
                    metrics
                }
            }
        }
    }

    @ViewBuilder
    private var metrics: some View {
        SummaryMetric(value: String(includedCount), label: "no vídeo")
        SummaryMetric(value: String(rejectedCount), label: "fora")
        SummaryMetric(value: duration.shortDuration, label: "duração")
    }

    private var title: String {
        includedCount == 1 ? "Uma jogada no vídeo." : "\(includedCount) jogadas no vídeo."
    }
}
