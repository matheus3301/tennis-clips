import SwiftUI

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case matches
    case practices
    case pending
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Todas"
        case .matches: "Jogos"
        case .practices: "Treinos"
        case .pending: "Para revisar"
        case .completed: "Concluídas"
        }
    }
}

struct SessionCard: View {
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
                        Text(
                            session.playedAt,
                            format: .dateTime.day().month(.wide).year().hour().minute()
                        )
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.ink.opacity(0.55))
                        if !session.opponent.isEmpty {
                            Text("vs. \(session.opponent)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppPalette.ink.opacity(0.68))
                        }
                        if session.displayLocation != nil || session.recordedDuration > 0 {
                            HStack(spacing: 10) {
                                if let location = session.displayLocation {
                                    Label(location, systemImage: "mappin.and.ellipse")
                                        .lineLimit(1)
                                }
                                if session.recordedDuration > 0 {
                                    Label(session.recordedDuration.shortDuration, systemImage: "clock")
                                        .accessibilityLabel(
                                            "Duração gravada, " + session.recordedDuration.spokenDuration
                                        )
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(AppPalette.ink.opacity(0.56))
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppPalette.ink.opacity(0.28))
                }

                RallyRail(decisions: session.sortedClips.map(\.decision), currentIndex: nil)

                HStack {
                    Label(session.status.label, systemImage: statusIcon)
                    Spacer()
                    if !session.clips.isEmpty {
                        Text(AppCopy.plays(session.clips.count))
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.ink.opacity(0.56))
            }
            .padding(16)
            .background(AppPalette.courtMist)
        }
        .background(AppPalette.courtMist)
        .clipShape(.rect(cornerRadius: 24))
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
