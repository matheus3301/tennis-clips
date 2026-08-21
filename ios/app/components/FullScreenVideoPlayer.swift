import AVKit
import SwiftUI

struct FullScreenVideoPlayer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()

            Button("Fechar tela cheia", systemImage: "xmark", action: dismiss.callAsFunction)
                .labelStyle(.iconOnly)
                .font(.body.bold())
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: .circle)
                .padding()
        }
        .background(.black)
        .onAppear {
            player.play()
        }
        .onDisappear {
            player.pause()
        }
    }
}
