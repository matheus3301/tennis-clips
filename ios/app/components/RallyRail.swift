import SwiftUI

struct RallyRail: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    let decisions: [RallyDecision]
    let currentIndex: Int?

    @ViewBuilder
    var body: some View {
        if decisions.count > 20 {
            aggregateRail
        } else {
            detailedRail
        }
    }

    private var detailedRail: some View {
        GeometryReader { geometry in
            let count = max(decisions.count, 1)
            let step = count == 1 ? 0 : geometry.size.width / CGFloat(count - 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppPalette.baseline.opacity(0.16))
                    .frame(height: 2)

                ForEach(decisions.indices, id: \.self) { index in
                    marker(for: decisions[index])
                        .position(
                            x: count == 1 ? geometry.size.width / 2 : CGFloat(index) * step,
                            y: geometry.size.height / 2
                        )
                }

                if let currentIndex, decisions.indices.contains(currentIndex) {
                    Circle()
                        .fill(AppPalette.ball)
                        .frame(width: 18, height: 18)
                        .shadow(color: AppPalette.ball.opacity(0.45), radius: 8)
                        .position(
                            x: count == 1 ? geometry.size.width / 2 : CGFloat(currentIndex) * step,
                            y: geometry.size.height / 2
                        )
                        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: currentIndex)
                }
            }
        }
        .frame(height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progresso da revisão")
        .accessibilityValue(accessibilityValue)
    }

    private var aggregateRail: some View {
        HStack(spacing: 8) {
            ProgressView(value: Double(reviewedCount), total: Double(max(decisions.count, 1)))
                .tint(AppPalette.baseline)
            Text("\(reviewedCount)/\(decisions.count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(AppPalette.ink.opacity(0.7))
        }
        .frame(height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progresso da revisão")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private func marker(for decision: RallyDecision) -> some View {
        switch decision {
        case .pending:
            Circle()
                .stroke(AppPalette.baseline.opacity(0.28), lineWidth: 1.5)
                .background(Circle().fill(AppPalette.chalk))
                .frame(width: 9, height: 9)
        case .kept:
            if differentiateWithoutColor {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppPalette.baseline)
            } else {
                Circle()
                    .fill(AppPalette.baseline)
                    .frame(width: 9, height: 9)
            }
        case .rejected:
            if differentiateWithoutColor {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppPalette.clayMark)
            } else {
                Circle()
                    .fill(AppPalette.clayMark.opacity(0.52))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private var reviewedCount: Int {
        decisions.filter { $0 != .pending }.count
    }

    private var accessibilityValue: String {
        AppCopy.reviewedPlays(reviewedCount, total: decisions.count)
    }
}
