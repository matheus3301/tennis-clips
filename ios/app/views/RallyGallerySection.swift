import SwiftUI

struct RallyGallerySection: View {
    let title: String
    let emptyTitle: String
    let emptySymbol: String
    let clips: [RallyClip]
    let session: TennisSession
    let singleColumn: Bool
    let onDecisionChange: (RallyClip, RallyDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.bold())
                    .tracking(1.5)
                    .foregroundStyle(AppPalette.ink)
                Spacer()
                Text(clips.count, format: .number)
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(.secondary)
            }

            if clips.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptySymbol)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppPalette.courtMist.opacity(0.34), in: .rect(cornerRadius: 18))
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(clips) { clip in
                        RallyGalleryCard(
                            session: session,
                            clip: clip,
                            onDecisionChange: onDecisionChange
                        )
                    }
                }
            }
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
            count: singleColumn ? 1 : 2
        )
    }
}
