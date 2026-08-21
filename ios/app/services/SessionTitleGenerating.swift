import CoreGraphics
import Foundation

@MainActor
protocol SessionTitleGenerating {
    var supportsVisualContext: Bool { get }

    func generate(
        for facts: SessionTitleFacts,
        style: TitleStyle,
        visualFrames: [CGImage]
    ) async -> SessionTitleGenerationOutcome
}
