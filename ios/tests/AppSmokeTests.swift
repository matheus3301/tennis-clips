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

    @MainActor
    func testChangingCompletedMontageMarksItReadyForRebuild() throws {
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
            start: 1,
            end: 5,
            impactCount: 2,
            confidence: 1,
            decision: .kept
        )
        session.clips = [clip]
        session.outputPath = "exports/compilation.mp4"
        session.status = .completed
        context.insert(session)
        let model = AppModel(analyzer: StubAnalyzer())

        model.decide(.rejected, for: clip, in: session, context: context)

        XCTAssertEqual(clip.decision, .rejected)
        XCTAssertEqual(session.status, .ready)
        XCTAssertEqual(session.outputPath, "exports/compilation.mp4")
    }

    func testImportedMoviePreservesDisplayName() {
        let movie = ImportedMovie(
            url: URL(fileURLWithPath: "/tmp/random.mov"),
            originalName: "Quadra 1.MOV"
        )
        XCTAssertEqual(movie.originalName, "Quadra 1.MOV")
    }

    func testISO6709LocationMetadataIsParsed() throws {
        let coordinate = try XCTUnwrap(
            MediaMetadataService.parseISO6709("-03.731900-038.526700+004.000/")
        )

        XCTAssertEqual(coordinate.latitude, -3.7319, accuracy: 0.000_001)
        XCTAssertEqual(coordinate.longitude, -38.5267, accuracy: 0.000_001)
    }

    @MainActor
    func testSessionAggregatesRecordedDurationAndLocation() {
        let session = TennisSession(kind: .practice, title: "Treino", playedAt: .now)
        session.locationName = "BNB Clube"
        session.videos = [
            SessionVideo(
                order: 0,
                originalName: "1.mov",
                relativePath: "sources/1.mov",
                duration: 120
            ),
            SessionVideo(
                order: 1,
                originalName: "2.mov",
                relativePath: "sources/2.mov",
                duration: 180
            ),
        ]

        XCTAssertEqual(session.recordedDuration, 300)
        XCTAssertEqual(session.displayLocation, "BNB Clube")
    }

    @MainActor
    func testAutomaticTitleStartsWithAnExplicitTemporaryState() {
        let session = TennisSession(
            kind: .practice,
            title: "",
            playedAt: .now,
            titleOrigin: .automatic
        )

        XCTAssertEqual(session.automaticTitleState, .pending)
        XCTAssertEqual(session.displayTitle, "Gerando título…")
    }

    func testDurationHasAccessibleSpokenFormat() {
        XCTAssertEqual(TimeInterval(1).spokenDuration, "1 segundo")
        XCTAssertEqual(TimeInterval(60).spokenDuration, "1 minuto")
        XCTAssertEqual(TimeInterval(125).spokenDuration, "2 minutos e 5 segundos")
    }

    @MainActor
    func testManualSessionEditProtectsTitleFromAutomaticUpdates() throws {
        let container = try ModelContainer(
            for: TennisSession.self,
            SessionVideo.self,
            RallyClip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let session = TennisSession(
            kind: .practice,
            title: "Treino à noite",
            playedAt: .now,
            titleOrigin: .automatic
        )
        container.mainContext.insert(session)
        let model = AppModel(analyzer: StubAnalyzer())

        XCTAssertTrue(model.updateSession(
            session,
            kind: .practice,
            title: "Meu treino",
            opponent: "",
            playedAt: session.playedAt,
            context: container.mainContext
        ))
        XCTAssertEqual(session.titleOrigin, .manual)
        XCTAssertEqual(session.automaticTitleState, .notApplicable)
        XCTAssertTrue(session.playedAtIsManual)
    }

    @MainActor
    func testRemovingRecordingRecomputesAutomaticMetadata() async throws {
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
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = earlier.addingTimeInterval(3_600)
        let session = TennisSession(
            kind: .practice,
            title: "Treino",
            playedAt: earlier,
            playedAtIsManual: false,
            titleOrigin: .manual
        )
        session.locationName = "Local antigo"
        session.latitude = -3.75
        session.longitude = -38.55
        let remaining = SessionVideo(
            order: 0,
            originalName: "1.mov",
            relativePath: "sources/source-001.mov",
            duration: 120,
            capturedAt: later,
            latitude: -3.73,
            longitude: -38.52
        )
        let removed = SessionVideo(
            order: 1,
            originalName: "2.mov",
            relativePath: "sources/source-002.mov",
            duration: 120,
            capturedAt: earlier,
            latitude: -3.77,
            longitude: -38.58
        )
        session.videos = [remaining, removed]
        context.insert(session)
        try storage.prepareSession(session.id)
        try Data([0]).write(to: storage.url(for: session.id, relativePath: remaining.relativePath))
        try Data([1]).write(to: storage.url(for: session.id, relativePath: removed.relativePath))
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(
            analyzer: StubAnalyzer(),
            storage: storage,
            locationResolver: StubLocationResolver()
        )

        try model.removeRecording(removed, from: session, context: context)

        let deadline = ContinuousClock.now + .seconds(2)
        while session.metadataVersion == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(session.playedAt, later)
        XCTAssertEqual(try XCTUnwrap(session.latitude), -3.73, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(session.longitude), -38.52, accuracy: 0.000_001)
        XCTAssertEqual(session.displayLocation, "Local recalculado")
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
        let session = TennisSession(kind: .practice, title: "Treino", playedAt: .now)
        session.clips = [clip]
        context.insert(session)
        let model = AppModel(analyzer: StubAnalyzer())

        let didSave = model.updateClipBounds(
            clip,
            start: 1.5,
            end: 8,
            in: session,
            context: context
        )

        XCTAssertTrue(didSave)
        XCTAssertEqual(clip.start, 1.5)
        XCTAssertEqual(clip.end, 8)
        XCTAssertEqual(clip.decision, .pending)
        XCTAssertEqual(session.status, .reviewing)
    }

    @MainActor
    func testCorrectingCompletedClipMarksMontageReadyForRebuild() throws {
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
            confidence: 1,
            decision: .kept
        )
        let session = TennisSession(kind: .practice, title: "Treino", playedAt: .now)
        session.clips = [clip]
        session.outputPath = "exports/compilation.mp4"
        session.status = .completed
        context.insert(session)
        let model = AppModel(analyzer: StubAnalyzer())

        XCTAssertTrue(model.updateClipBounds(
            clip,
            start: 1.5,
            end: 8,
            in: session,
            context: context
        ))

        XCTAssertEqual(clip.decision, .kept)
        XCTAssertEqual(session.status, .ready)
        XCTAssertEqual(session.outputPath, "exports/compilation.mp4")
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
            confidence: 0.8,
            decision: .kept
        )
        session.clips = [clip]
        context.insert(session)
        let model = AppModel(analyzer: StubAnalyzer())

        XCTAssertTrue(model.splitClip(clip, in: session, context: context))
        XCTAssertEqual(session.sortedClips.count, 2)
        XCTAssertEqual(session.sortedClips[0].end, 6)
        XCTAssertEqual(session.sortedClips[1].start, 6)
        XCTAssertEqual(session.sortedClips.map(\.decision), [.kept, .kept])
        XCTAssertEqual(session.status, .ready)

        XCTAssertTrue(model.mergeWithNextClip(clip, in: session, context: context))
        XCTAssertEqual(session.clips.count, 1)
        XCTAssertEqual(clip.start, 2)
        XCTAssertEqual(clip.end, 10)
        XCTAssertEqual(clip.decision, .kept)
        XCTAssertEqual(session.status, .ready)
    }

    @MainActor
    func testSplittingMiddleClipPreservesOrderDecisionAndImpactCount() throws {
        let container = try ModelContainer(
            for: TennisSession.self,
            SessionVideo.self,
            RallyClip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let videoID = UUID()
        let session = TennisSession(kind: .practice, title: "Treino", playedAt: .now)
        let first = RallyClip(
            sourceVideoID: videoID,
            order: 0,
            start: 0,
            end: 2,
            impactCount: 1,
            confidence: 1,
            decision: .kept
        )
        let middle = RallyClip(
            sourceVideoID: videoID,
            order: 1,
            start: 3,
            end: 7,
            impactCount: 1,
            confidence: 1,
            decision: .rejected
        )
        let last = RallyClip(
            sourceVideoID: videoID,
            order: 2,
            start: 8,
            end: 12,
            impactCount: 2,
            confidence: 1,
            decision: .kept
        )
        session.clips = [first, middle, last]
        context.insert(session)
        let model = AppModel(analyzer: StubAnalyzer())

        XCTAssertTrue(model.splitClip(middle, in: session, context: context))

        XCTAssertEqual(session.sortedClips.map(\.order), [0, 1, 2, 3])
        XCTAssertEqual(session.sortedClips.map(\.decision), [.kept, .rejected, .rejected, .kept])
        XCTAssertEqual(session.sortedClips[1].impactCount + session.sortedClips[2].impactCount, 1)
        XCTAssertEqual(session.status, .ready)
    }

    @MainActor
    func testMergingClipsWithDifferentDecisionsIsRejectedWithoutMutation() throws {
        let container = try ModelContainer(
            for: TennisSession.self,
            SessionVideo.self,
            RallyClip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let videoID = UUID()
        let session = TennisSession(kind: .practice, title: "Treino", playedAt: .now)
        let included = RallyClip(
            sourceVideoID: videoID,
            order: 0,
            start: 1,
            end: 4,
            impactCount: 1,
            confidence: 1,
            decision: .kept
        )
        let rejected = RallyClip(
            sourceVideoID: videoID,
            order: 1,
            start: 5,
            end: 8,
            impactCount: 1,
            confidence: 1,
            decision: .rejected
        )
        session.clips = [included, rejected]
        context.insert(session)
        let model = AppModel(analyzer: StubAnalyzer())

        XCTAssertFalse(model.mergeWithNextClip(included, in: session, context: context))

        XCTAssertEqual(session.sortedClips.map(\.id), [included.id, rejected.id])
        XCTAssertEqual(included.end, 4)
        XCTAssertEqual(included.decision, .kept)
        XCTAssertEqual(rejected.decision, .rejected)
        XCTAssertEqual(model.notice?.message, "Para unir, coloque as duas jogadas no mesmo grupo primeiro.")
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

@MainActor
private struct StubLocationResolver: SessionLocationResolving {
    func resolve(latitude: Double, longitude: Double) async -> ResolvedSessionLocation? {
        ResolvedSessionLocation(name: "Local recalculado", locality: "Fortaleza")
    }
}
