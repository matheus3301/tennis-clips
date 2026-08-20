import CoreGraphics
import Foundation

@MainActor
protocol SessionTitleGenerating {
    var supportsVisualContext: Bool { get }

    func fallback(for facts: SessionTitleFacts, style: TitleStyle) -> String

    func generate(
        for facts: SessionTitleFacts,
        style: TitleStyle,
        visualFrames: [CGImage]
    ) async -> String?
}
