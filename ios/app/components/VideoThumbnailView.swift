@preconcurrency import AVFoundation
import SwiftUI
import UIKit

private actor VideoThumbnailLoader {
    static let shared = VideoThumbnailLoader()

    func image(url: URL, time: TimeInterval) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        let requested = CMTime(seconds: max(time, 0), preferredTimescale: 600)
        guard let image = try? generator.copyCGImage(at: requested, actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}

struct VideoThumbnailView: View {
    let url: URL?
    // A small offset avoids the black encoder lead-in that is common in
    // freshly exported compilations while still representing the opening shot.
    var time: TimeInterval = 0.25

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            AppPalette.hardCourt
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                CourtGlyph()
                    .stroke(AppPalette.chalk.opacity(0.76), lineWidth: 1.5)
                    .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: taskID) {
            guard let url else { return }
            image = await VideoThumbnailLoader.shared.image(url: url, time: time)
        }
    }

    private var taskID: String {
        (url?.path ?? "none") + "#" + String(time)
    }
}

struct CourtGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addRect(rect.insetBy(dx: rect.width * 0.2, dy: rect.height * 0.26))
        return path
    }
}
