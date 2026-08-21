import SwiftUI

struct SessionMetadataSummary: View {
    let session: TennisSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SOBRE A SESSÃO")
                .font(.caption.bold())
                .tracking(1.4)
                .foregroundStyle(AppPalette.hardCourt)

            Label {
                Text(session.playedAt, format: .dateTime.day().month(.wide).year().hour().minute())
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

            AutomaticTitleStatusView(session: session)
        }
        .font(.subheadline)
        .foregroundStyle(AppPalette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppPalette.courtMist.opacity(0.58), in: .rect(cornerRadius: 18))
    }
}
