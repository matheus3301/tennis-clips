import SwiftUI
import TennisClipsCore

struct ProcessingView: View {
    let update: ProcessingUpdate

    var body: some View {
        VStack(spacing: 34) {
            Spacer()
            RallyProgress(fraction: update.fraction)
                .frame(height: 150)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                Text(update.stage.title)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(AppPalette.ink)
                Text(update.fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .foregroundStyle(AppPalette.clay)
            }
            Spacer()
            Label("Pode manter o app aberto; nada está sendo enviado.", systemImage: "lock.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppPalette.ink.opacity(0.54))
                .padding(.bottom, 24)
        }
    }
}

private struct RallyProgress: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 32
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 28)
                    .fill(AppPalette.courtBlue)
                Path { path in
                    path.move(to: CGPoint(x: 16, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width - 16, y: geometry.size.height / 2))
                }
                .stroke(AppPalette.line.opacity(0.4), lineWidth: 2)
                Circle()
                    .fill(AppPalette.ball)
                    .frame(width: 30, height: 30)
                    .shadow(color: AppPalette.ball.opacity(0.45), radius: 12)
                    .offset(x: max(16, width * fraction), y: 0)
            }
        }
    }
}
