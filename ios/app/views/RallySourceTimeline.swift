import SwiftUI

struct RallySourceTimeline: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let video: SessionVideo
    let clips: [RallyClip]
    let selectedClipID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(video.originalName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                Text(video.duration.shortDuration)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Canvas { context, size in
                let track = Path(
                    roundedRect: CGRect(x: 0, y: 12, width: size.width, height: 6),
                    cornerRadius: 3
                )
                context.fill(track, with: .color(AppPalette.courtMist))

                for clip in clips {
                    drawSegment(for: clip, in: size, context: &context)
                }
            }
            .frame(height: 30)

            HStack {
                Text("00:00")
                Spacer()
                Text(video.duration.shortDuration)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(AppPalette.courtMist.opacity(0.38), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private func drawSegment(
        for clip: RallyClip,
        in size: CGSize,
        context: inout GraphicsContext
    ) {
        let duration = max(video.duration, 0.1)
        let segmentWidth = min(size.width, max(7, size.width * clip.duration / duration))
        let midpoint = (clip.start + clip.end) / 2
        let center = min(
            max(segmentWidth / 2, size.width * midpoint / duration),
            size.width - segmentWidth / 2
        )
        let selected = clip.id == selectedClipID
        let segmentHeight: Double = selected ? 22 : 13
        let rect = CGRect(
            x: center - segmentWidth / 2,
            y: 15 - segmentHeight / 2,
            width: segmentWidth,
            height: segmentHeight
        )
        let segment = Path(roundedRect: rect, cornerRadius: 3)
        let strokeStyle = StrokeStyle(
            lineWidth: selected ? 3 : 1,
            dash: differentiateWithoutColor && clip.decision == .rejected ? [3, 2] : []
        )

        context.fill(segment, with: .color(color(for: clip)))
        context.stroke(
            segment,
            with: .color(selected ? AppPalette.ball : patternColor(for: clip)),
            style: strokeStyle
        )
    }

    private func color(for clip: RallyClip) -> Color {
        switch clip.decision {
        case .kept: AppPalette.hardCourt
        case .rejected: AppPalette.clayMark.opacity(0.62)
        case .pending: AppPalette.baseline.opacity(0.26)
        }
    }

    private func patternColor(for clip: RallyClip) -> Color {
        differentiateWithoutColor && clip.decision == .rejected ? AppPalette.ink : .clear
    }

    private var accessibilityDescription: String {
        guard let selected = clips.first(where: { $0.id == selectedClipID }) else {
            return "Timeline da gravação \(video.originalName)"
        }
        return "Timeline da gravação \(video.originalName). Jogada selecionada de \(selected.start.shortDuration) a \(selected.end.shortDuration)"
    }
}
