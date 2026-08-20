import AVFoundation
import SwiftUI
import UIKit

struct RallyPlayerView: View {
    let url: URL
    let start: TimeInterval
    let end: TimeInterval
    @Binding private var isPlaying: Bool

    @State private var player = AVPlayer()

    init(
        url: URL,
        start: TimeInterval,
        end: TimeInterval,
        isPlaying: Binding<Bool> = .constant(true)
    ) {
        self.url = url
        self.start = start
        self.end = end
        _isPlaying = isPlaying
    }

    var body: some View {
        AspectFillPlayerView(player: player)
            .onAppear(perform: configure)
            .onChange(of: clipKey) { _, _ in configure() }
            .onChange(of: isPlaying) { _, shouldPlay in
                shouldPlay ? player.play() : player.pause()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            ) { notification in
                guard notification.object as? AVPlayerItem === player.currentItem else { return }
                restart()
            }
            .onDisappear { player.pause() }
    }

    private var clipKey: String {
        url.path + "#" + String(start) + "#" + String(end)
    }

    private func configure() {
        let item = AVPlayerItem(url: url)
        item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        player.replaceCurrentItem(with: item)
        restart()
    }

    private func restart() {
        Task {
            let finished = await player.seek(
                to: CMTime(seconds: start, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            if finished, isPlaying { player.play() }
        }
    }
}

struct AspectFillPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        view.playerLayer.player = player
    }
}

final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
