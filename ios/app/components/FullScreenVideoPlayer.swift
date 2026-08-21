import AVKit
import SwiftUI

struct FullScreenVideoPlayer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VideoPlayer(player: player)
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack {
                        Button(
                            "Fechar",
                            systemImage: "xmark",
                            action: dismiss.callAsFunction
                        )
                        .font(.body.bold())
                        .foregroundStyle(.white)
                        .frame(minHeight: 44)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(.black)
                }
                .ignoresSafeArea(edges: .bottom)
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
