import SwiftUI

struct RallyRail: View {
    let decisions: [RallyDecision]
    let currentIndex: Int?

    var body: some View {
        GeometryReader { geometry in
            let count = max(decisions.count, 1)
            let step = count == 1 ? 0 : geometry.size.width / CGFloat(count - 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppPalette.baseline.opacity(0.16))
                    .frame(height: 2)

                ForEach(Array(decisions.enumerated()), id: \.offset) { index, decision in
                    marker(for: decision)
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

    @ViewBuilder
    private func marker(for decision: RallyDecision) -> some View {
        switch decision {
        case .pending:
            Circle()
                .stroke(AppPalette.baseline.opacity(0.28), lineWidth: 1.5)
                .background(Circle().fill(AppPalette.chalk))
                .frame(width: 9, height: 9)
        case .kept:
            Circle()
                .fill(AppPalette.baseline)
                .frame(width: 9, height: 9)
        case .rejected:
            Circle()
                .fill(AppPalette.clayMark.opacity(0.36))
                .frame(width: 7, height: 7)
        }
    }

    private var accessibilityValue: String {
        let reviewed = decisions.filter { $0 != .pending }.count
        return "\(reviewed) de \(decisions.count) jogadas revisadas"
    }
}
