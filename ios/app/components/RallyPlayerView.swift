import AVFoundation
import SwiftUI
import UIKit

struct RallyPlayerView: View {
    let url: URL
    let start: TimeInterval
    let end: TimeInterval

    @State private var player = AVPlayer()

    var body: some View {
        AspectFillPlayerView(player: player)
            .onAppear(perform: configure)
            .onChange(of: clipKey) { _, _ in configure() }
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
        player.seek(
            to: CMTime(seconds: start, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { finished in
            if finished { player.play() }
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
