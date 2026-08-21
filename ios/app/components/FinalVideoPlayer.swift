import AVKit
import SwiftUI

struct FinalVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer
    @State private var isPlaying = false

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack {
            if isPlaying {
                AspectFillPlayerView(player: player)
                    .transition(.opacity)
            } else {
                VideoThumbnailView(url: url)
            }

            Button(action: togglePlayback) {
                ZStack {
                    Color.clear
                    if !isPlaying {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 72, height: 72)
                        Image(systemName: "play.fill")
                            .font(.title2.bold())
                            .foregroundStyle(AppPalette.chalk)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pausar vídeo" : "Reproduzir vídeo")
        }
        .background(AppPalette.hardCourt)
        .animation(.easeOut(duration: 0.2), value: isPlaying)
        .onDisappear {
            player.pause()
            isPlaying = false
        }
    }

    private func togglePlayback() {
        isPlaying.toggle()
        isPlaying ? player.play() : player.pause()
    }
}
