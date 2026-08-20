import SwiftUI

struct RallyGalleryCard: View {
    @Environment(AppModel.self) private var model

    let session: TennisSession
    let clip: RallyClip
    let onDecisionChange: (RallyClip, RallyDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: AppRoute.rally(session.id, clip.id)) {
                VStack(alignment: .leading, spacing: 10) {
                    VideoThumbnailView(
                        url: model.sourceURL(for: clip, in: session),
                        time: clip.start + min(0.25, clip.duration / 2),
                        maximumPixelSize: 360
                    )
                    .frame(height: 116)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: statusSymbol)
                            .font(.subheadline.bold())
                            .foregroundStyle(statusColor)
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(8)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Jogada \(clip.order + 1)")
                            .font(.headline)
                            .foregroundStyle(AppPalette.ink)
                        Text("\(clip.duration.shortDuration) · \(impactDescription)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityDescription)
            .padding(12)

            Divider()

            Button(action: toggleDecision) {
                Label(actionTitle, systemImage: actionSymbol)
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(actionColor)
            .accessibilityHint(actionHint)
        }
        .background(AppPalette.courtMist.opacity(0.52), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(statusColor.opacity(0.34), lineWidth: 1)
        }
    }

    private var isIncluded: Bool { clip.decision == .kept }
    private var statusColor: Color { isIncluded ? AppPalette.hardCourt : AppPalette.clayMark }
    private var actionColor: Color { isIncluded ? AppPalette.clayMark : AppPalette.hardCourt }
    private var statusSymbol: String { isIncluded ? "checkmark.circle.fill" : "xmark.circle.fill" }
    private var actionTitle: String { isIncluded ? "Retirar do vídeo" : "Incluir no vídeo" }
    private var actionSymbol: String { isIncluded ? "minus.circle" : "plus.circle" }
    private var actionHint: String {
        isIncluded ? "Move esta jogada para Fora do vídeo" : "Move esta jogada para No vídeo"
    }
    private var impactDescription: String {
        clip.impactCount == 1 ? "1 batida" : "\(clip.impactCount) batidas"
    }
    private var accessibilityDescription: String {
        let status = isIncluded ? "no vídeo" : "fora do vídeo"
        return "Jogada \(clip.order + 1), \(status), duração \(clip.duration.shortDuration), \(impactDescription)"
    }

    private func toggleDecision() {
        onDecisionChange(clip, isIncluded ? .rejected : .kept)
    }
}
