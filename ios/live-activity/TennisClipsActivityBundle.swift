import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TennisClipsActivityBundle: WidgetBundle {
    var body: some Widget {
        TennisProcessingLiveActivity()
    }
}

struct TennisProcessingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TennisProcessingAttributes.self) { context in
            LockScreenProcessingView(context: context)
                .activityBackgroundTint(Color(red: 0.08, green: 0.19, blue: 0.24))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Tennis Clips", systemImage: "figure.tennis")
                        .font(.caption.weight(.bold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit().weight(.bold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.stage)
                            .font(.headline)
                        ProgressView(value: context.state.progress)
                            .tint(Color(red: 0.84, green: 0.92, blue: 0.31))
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.tennis")
                    .foregroundStyle(Color(red: 0.84, green: 0.92, blue: 0.31))
            } compactTrailing: {
                Text(context.state.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption2.monospacedDigit().weight(.bold))
            } minimal: {
                Circle()
                    .trim(from: 0, to: context.state.progress)
                    .stroke(
                        Color(red: 0.84, green: 0.92, blue: 0.31),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(3)
            }
            .keylineTint(Color(red: 0.84, green: 0.92, blue: 0.31))
        }
    }
}

private struct LockScreenProcessingView: View {
    let context: ActivityViewContext<TennisProcessingAttributes>

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color(red: 0.84, green: 0.92, blue: 0.31))
                Image(systemName: "figure.tennis")
                    .foregroundStyle(Color(red: 0.08, green: 0.19, blue: 0.24))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.state.stage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: context.state.progress)
                    .tint(Color(red: 0.84, green: 0.92, blue: 0.31))
            }

            Text(context.state.progress, format: .percent.precision(.fractionLength(0)))
                .font(.headline.monospacedDigit())
        }
        .padding(16)
    }
}
