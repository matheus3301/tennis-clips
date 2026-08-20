import SwiftUI

struct FailureView: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 50, weight: .bold))
                .foregroundStyle(AppPalette.clay)
            Text("Esse treino não fechou")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(AppPalette.ink)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppPalette.ink.opacity(0.64))
            Button("Escolher outro vídeo") { model.startOver() }
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .foregroundStyle(AppPalette.chalk)
                .background(AppPalette.court, in: Capsule())
        }
        .padding(28)
    }
}
