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

    func testPhotoLibraryExporterCanBeCreatedOutsideMainActor() {
        _ = PhotoLibraryExporter()
    }

    @MainActor
    func testCreatingFirstSessionPreparesStorageBeforeCapacityValidation() throws {
        let sandboxRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageRoot = sandboxRoot
            .appendingPathComponent("TennisClips", isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)
        let sourceURL = sandboxRoot.appendingPathComponent("selected.mov")
        try FileManager.default.createDirectory(
            at: sandboxRoot,
            withIntermediateDirectories: true
        )
        try Data([0]).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sandboxRoot) }

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: storageRoot.deletingLastPathComponent().path
        ))

        let container = try ModelContainer(
            for: TennisSession.self,
            SessionVideo.self,
            RallyClip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let model = AppModel(
            analyzer: StubAnalyzer(),
            storage: SessionStorage(rootURL: storageRoot)
        )

        let session = try model.createSession(
            kind: .practice,
            title: "Primeiro treino",
            opponent: "",
            playedAt: .now,
            movies: [ImportedMovie(url: sourceURL, originalName: "selected.mov")],
            context: container.mainContext
        )

        model.cancelProcessing(session, context: container.mainContext)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: storageRoot.deletingLastPathComponent().path
        ))
        XCTAssertEqual(session.videos.count, 1)
    }

    @MainActor
    func testContinuedProcessingLaunchHandlerUsesMainQueue() async {
        let callback = expectation(description: "continued processing launch callback")

        ContinuedProcessingService.launchQueue.async {
            XCTAssertTrue(Thread.isMainThread)
            callback.fulfill()
        }

        await fulfillment(of: [callback], timeout: 1)
    }

    func testContinuedProcessingUsesUniqueIdentifierForEveryAttempt() {
        let sessionID = UUID()
        let first = ContinuedProcessingService.identifier(
            sessionID: sessionID,
            operationName: "analysis",
            attemptID: UUID()
        )
        let second = ContinuedProcessingService.identifier(
            sessionID: sessionID,
            operationName: "analysis",
            attemptID: UUID()
        )

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.hasPrefix("dev.mmonteiro.tennisclips.processing.analysis."))
    }

    @MainActor
    func testAnalysisIgnoresConcurrentRetry() throws {
        let container = try ModelContainer(
            for: TennisSession.self,
            SessionVideo.self,
            RallyClip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let session = TennisSession(kind: .practice, title: "Treino", playedAt: .now)
        container.mainContext.insert(session)
        let model = AppModel(analyzer: StubAnalyzer())

        XCTAssertTrue(model.startAnalysis(session, context: container.mainContext))
        XCTAssertFalse(model.startAnalysis(session, context: container.mainContext))

        model.cancelProcessing(session, context: container.mainContext)
    }

    @MainActor
    func testAnalysisKeepsValidClipsWhenOneVideoFails() async throws {
        let container = try ModelContainer(
            for: TennisSession.self,
            SessionVideo.self,
            RallyClip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let session = TennisSession(kind: .practice, title: "Treino", playedAt: .now)
        session.videos = [
            SessionVideo(order: 0, originalName: "sem-jogadas.mov", relativePath: "sources/source-001.mov"),
            SessionVideo(order: 1, originalName: "com-jogadas.mov", relativePath: "sources/source-002.mov"),
        ]
        context.insert(session)

        let storageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let model = AppModel(
            analyzer: PartialSuccessAnalyzer(),
            storage: SessionStorage(rootURL: storageRoot)
        )

        model.startAnalysis(session, context: context)

        let deadline = ContinuousClock.now + .seconds(3)
        while session.status == .analyzing, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(session.status, .reviewing)
        XCTAssertEqual(session.clips.count, 1)
        XCTAssertEqual(session.clips.first?.sourceVideoID, session.sortedVideos[1].id)
        XCTAssertEqual(
            session.errorMessage,
            "sem-jogadas.mov não gerou jogadas. A outra foi processada normalmente."
        )
    }

    @MainActor
    func testClipBoundsCanBeCorrectedWithoutChangingDecision() throws {
        let container = try ModelContainer(
            for: TennisSession.self,
            SessionVideo.self,
            RallyClip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let clip = RallyClip(
            sourceVideoID: UUID(),
            order: 0,
            start: 2,
            end: 7,
            impactCount: 2,
            confidence: 1
        )
        context.insert(clip)
        let model = AppModel(analyzer: StubAnalyzer())

        let didSave = model.updateClipBounds(clip, start: 1.5, end: 8, context: context)

        XCTAssertTrue(didSave)
        XCTAssertEqual(clip.start, 1.5)
        XCTAssertEqual(clip.end, 8)
        XCTAssertEqual(clip.decision, .pending)
    }

    @MainActor
    func testCompilationWithoutIncludedClipsProducesWarning() throws {
        let session = TennisSession(kind: .match, title: "Final", playedAt: .now)
        let model = AppModel(analyzer: StubAnalyzer())
        let container = try ModelContainer(
            for: TennisSession.self,
            SessionVideo.self,
            RallyClip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        model.compile(session, context: container.mainContext)

        XCTAssertEqual(model.notice?.kind, .warning)
        XCTAssertEqual(model.notice?.message, "Inclua pelo menos uma jogada antes de montar o vídeo.")
    }

    func testStagedSessionRemovalCanBeRestored() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = SessionStorage(rootURL: root)
        let sessionID = UUID()
        try storage.prepareSession(sessionID)
        let source = storage.url(for: sessionID, relativePath: "sources/source-001.mov")
        try Data([0, 1, 2]).write(to: source)

        let staged = try XCTUnwrap(storage.stageRemoval(sessionID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.sessionURL(sessionID).path))

        try storage.restoreStagedRemoval(staged, sessionID: sessionID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        try? FileManager.default.removeItem(at: root)
    }

    func testLiveActivityDeepLinkTargetsSession() {
        let id = UUID()
        let attributes = TennisProcessingAttributes(sessionID: id.uuidString, title: "Treino")

        XCTAssertEqual(attributes.deepLinkURL?.absoluteString, "tennisclips://session/\(id.uuidString)")
    }

    func testCurrentSchemaVersionIsExplicit() {
        XCTAssertEqual(TennisClipsSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(TennisClipsMigrationPlan.schemas.count, 1)
    }

    @MainActor
    func testClipCanBeSplitAndMergedBack() throws {
        let container = try ModelContainer(
            for: TennisSession.self,
            SessionVideo.self,
            RallyClip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let session = TennisSession(kind: .practice, title: "Treino", playedAt: .now)
        let clip = RallyClip(
            sourceVideoID: UUID(),
            order: 0,
            start: 2,
            end: 10,
            impactCount: 4,
            confidence: 0.8
        )
        session.clips = [clip]
        context.insert(session)
        let model = AppModel(analyzer: StubAnalyzer())

        XCTAssertTrue(model.splitClip(clip, in: session, context: context))
        XCTAssertEqual(session.sortedClips.count, 2)
        XCTAssertEqual(session.sortedClips[0].end, 6)
        XCTAssertEqual(session.sortedClips[1].start, 6)

        XCTAssertTrue(model.mergeWithNextClip(clip, in: session, context: context))
        XCTAssertEqual(session.clips.count, 1)
        XCTAssertEqual(clip.start, 2)
        XCTAssertEqual(clip.end, 10)
    }

    @MainActor
    func testRemovingRecordingKeepsAtLeastOneAndRestartsAnalysis() throws {
        let container = try ModelContainer(
            for: TennisSession.self,
            SessionVideo.self,
            RallyClip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = SessionStorage(rootURL: root)
        let session = TennisSession(kind: .match, title: "Jogo", playedAt: .now)
        let first = SessionVideo(order: 0, originalName: "1.mov", relativePath: "sources/source-001.mov")
        let second = SessionVideo(order: 1, originalName: "2.mov", relativePath: "sources/source-002.mov")
        session.videos = [first, second]
        context.insert(session)
        try storage.prepareSession(session.id)
        try Data([0]).write(to: storage.url(for: session.id, relativePath: first.relativePath))
        try Data([1]).write(to: storage.url(for: session.id, relativePath: second.relativePath))
        let model = AppModel(analyzer: StubAnalyzer(), storage: storage)

        try model.removeRecording(second, from: session, context: context)

        XCTAssertEqual(session.videos.map(\.id), [first.id])
        XCTAssertEqual(session.status, .analyzing)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: storage.url(for: session.id, relativePath: second.relativePath).path
        ))
        model.cancelProcessing(session, context: context)
        XCTAssertThrowsError(try model.removeRecording(first, from: session, context: context))
        try? FileManager.default.removeItem(at: root)
    }
}

nonisolated private struct StubAnalyzer: TennisAnalyzing {
    func analyze(
        videoAt url: URL,
        progress: @escaping @MainActor @Sendable (ProcessingUpdate) -> Void
    ) async throws -> VideoAnalysis {
        VideoAnalysis(duration: 0, impacts: [], clips: [])
    }
}

nonisolated private struct PartialSuccessAnalyzer: TennisAnalyzing {
    func analyze(
        videoAt url: URL,
        progress: @escaping @MainActor @Sendable (ProcessingUpdate) -> Void
    ) async throws -> VideoAnalysis {
        await progress(ProcessingUpdate(stage: .findingImpacts, fraction: 0.5))
        if url.lastPathComponent == "source-001.mov" {
            throw ProcessingError.noImpacts
        }
        let impact = ImpactEvent(
            time: 3,
            score: 1,
            amplitude: 1,
            midEnergyRatio: 0.2,
            highEnergyRatio: 0.1
        )
        return VideoAnalysis(
            duration: 12,
            impacts: [impact],
            clips: [ClipRange(start: 1, end: 6)]
        )
    }
}
