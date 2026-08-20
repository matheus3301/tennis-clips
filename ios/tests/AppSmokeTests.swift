import SwiftData
import TennisClipsCore
import XCTest
@testable import TennisClips

final class AppSmokeTests: XCTestCase {
    @MainActor
    func testSessionDefaultsToAnalyzing() {
        let session = TennisSession(
            kind: .match,
            title: "Jogo de quinta",
            playedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(session.status, .analyzing)
        XCTAssertEqual(session.displayTitle, "Jogo de quinta")
        XCTAssertEqual(session.progress, 0)
    }

    @MainActor
    func testReviewBecomesReadyAfterEveryClipHasADecision() throws {
        let container = try ModelContainer(
            for: TennisSession.self,
            SessionVideo.self,
            RallyClip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let session = TennisSession(kind: .practice, title: "", playedAt: .now)
        let videoID = UUID()
        let first = RallyClip(
            sourceVideoID: videoID,
            order: 0,
            start: 1,
            end: 4,
            impactCount: 2,
            confidence: 1
        )
        let second = RallyClip(
            sourceVideoID: videoID,
            order: 1,
            start: 6,
            end: 10,
            impactCount: 3,
            confidence: 1
        )
        session.clips = [first, second]
        context.insert(session)
        let model = AppModel(analyzer: StubAnalyzer())

        model.decide(.kept, for: first, in: session, context: context)
        XCTAssertEqual(session.status, .reviewing)

        model.decide(.rejected, for: second, in: session, context: context)
        XCTAssertEqual(session.status, .ready)
        XCTAssertEqual(session.keptClips.map(\.id), [first.id])
    }

    func testImportedMoviePreservesDisplayName() {
        let movie = ImportedMovie(
            url: URL(fileURLWithPath: "/tmp/random.mov"),
            originalName: "Quadra 1.MOV"
        )
        XCTAssertEqual(movie.originalName, "Quadra 1.MOV")
    }
}

private struct StubAnalyzer: TennisAnalyzing {
    func analyze(
        videoAt url: URL,
        progress: @escaping @MainActor @Sendable (ProcessingUpdate) -> Void
    ) async throws -> VideoAnalysis {
        VideoAnalysis(duration: 0, impacts: [], clips: [])
    }
}
