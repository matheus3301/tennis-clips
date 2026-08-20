import SwiftUI

struct SessionMetadataSummary: View {
    let session: TennisSession

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                Label {
                    Text(session.playedAt, format: .dateTime.day().month().hour().minute())
                } icon: {
                    Image(systemName: "calendar")
                }
                if session.recordedDuration > 0 {
                    Label(session.recordedDuration.shortDuration, systemImage: "clock")
                        .accessibilityLabel(
                            "Duração gravada, " + session.recordedDuration.spokenDuration
                        )
                }
                if let location = session.displayLocation {
                    Label(location, systemImage: "mappin.and.ellipse")
                }
            }
            .font(.subheadline)
            .foregroundStyle(AppPalette.ink.opacity(0.7))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .background(AppPalette.courtMist)
        .accessibilityElement(children: .combine)
    }
}
