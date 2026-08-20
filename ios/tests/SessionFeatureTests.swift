@preconcurrency import AVFoundation
import CoreGraphics
import SwiftData
import TennisClipsCore
import XCTest
@testable import TennisClips

final class SessionFeatureTests: XCTestCase {
    func testTitleStyleExposesStableSettingsCopy() {
        XCTAssertEqual(TitleStyle.allCases, [.standard, .creative])
        XCTAssertEqual(TitleStyle.standard.id, TitleStyle.standard.rawValue)
        XCTAssertEqual(TitleStyle.standard.title, "Padrão")
        XCTAssertEqual(TitleStyle.creative.title, "Criativo")
        XCTAssertTrue(TitleStyle.standard.description.contains("factuais"))
        XCTAssertTrue(TitleStyle.creative.description.contains("no aparelho"))
    }

    func testCurrentTitleStyleUsesStoredValueAndFallsBackForInvalidValue() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: "titleStyle")
        defer { restore(previousValue, forKey: "titleStyle", in: defaults) }

        defaults.set(TitleStyle.creative.rawValue, forKey: "titleStyle")
        XCTAssertEqual(TitleStyle.current, .creative)

        defaults.set("desconhecido", forKey: "titleStyle")
        XCTAssertEqual(TitleStyle.current, .standard)

        defaults.removeObject(forKey: "titleStyle")
        XCTAssertEqual(TitleStyle.current, .standard)
    }

    func testSessionTitleFactsClassifiesEveryPeriodOfDay() throws {
        XCTAssertEqual(try facts(atHour: 4).periodOfDay, "de madrugada")
        XCTAssertEqual(try facts(atHour: 5).periodOfDay, "pela manhã")
        XCTAssertEqual(try facts(atHour: 11).periodOfDay, "pela manhã")
        XCTAssertEqual(try facts(atHour: 12).periodOfDay, "à tarde")
        XCTAssertEqual(try facts(atHour: 17).periodOfDay, "à tarde")
        XCTAssertEqual(try facts(atHour: 18).periodOfDay, "à noite")
        XCTAssertEqual(try facts(atHour: 23).periodOfDay, "à noite")
        XCTAssertEqual(try facts(atHour: 0).periodOfDay, "de madrugada")
    }

    @MainActor
    func testFallbackTitlesCoverStylesWithAndWithoutLocation() throws {
        let generator = SessionTitleGenerator()
        let morning = try facts(atHour: 8, location: nil)

        XCTAssertEqual(generator.fallback(for: morning, style: .standard), "Treino pela manhã")
        XCTAssertEqual(generator.fallback(for: morning, style: .creative), "Treino pela manhã")

        let atClub = try facts(atHour: 8, location: "Clube do Lago")
        XCTAssertEqual(generator.fallback(for: atClub, style: .standard), "Treino no Clube do Lago")
        XCTAssertEqual(
            generator.fallback(for: atClub, style: .creative),
            "Treino pela manhã no Clube do Lago"
        )
    }

    func testGeneratedTitleValidationEnforcesPromptContract() {
        XCTAssertEqual(SessionTitleGenerator.validated("  Treino intenso.  "), "Treino intenso")
        XCTAssertNil(SessionTitleGenerator.validated("Treino"))
        XCTAssertNil(SessionTitleGenerator.validated("um dois três quatro cinco seis sete oito nove"))
        XCTAssertNil(SessionTitleGenerator.validated("Treino\nintenso"))
        XCTAssertNil(SessionTitleGenerator.validated(String(repeating: "a", count: 81) + " b"))
    }

    func testPromptValuesCollapseWhitespaceAndLimitUserControlledText() {
        XCTAssertEqual(
            SessionTitleGenerator.promptValue("  Clube\n do\tLago\r "),
            "Clube do Lago"
        )
        XCTAssertEqual(
            SessionTitleGenerator.promptValue(String(repeating: "a", count: 200)).count,
            120
        )
    }

    func testISO6709ParserSupportsAltitudeAndRejectsInvalidCoordinates() throws {
        let coordinate = try XCTUnwrap(
            MediaMetadataService.parseISO6709("+40.689200-074.044500+012.000/")
        )
        XCTAssertEqual(coordinate.latitude, 40.6892, accuracy: 0.000_001)
        XCTAssertEqual(coordinate.longitude, -74.0445, accuracy: 0.000_001)

        XCTAssertNil(MediaMetadataService.parseISO6709("40.6892,-74.0445"))
        XCTAssertNil(MediaMetadataService.parseISO6709("+91.0000-038.0000/"))
        XCTAssertNil(MediaMetadataService.parseISO6709("-03.0000-181.0000/"))
        XCTAssertNil(MediaMetadataService.parseISO6709("+abc-038.0000/"))
    }

    func testMetadataItemsExposeCaptureDateAndCoordinate() async throws {
        let dateItem = AVMutableMetadataItem()
        dateItem.identifier = .commonIdentifierCreationDate
        dateItem.value = "2026-08-20T18:30:00-03:00" as NSString
        let locationItem = AVMutableMetadataItem()
        locationItem.identifier = .quickTimeMetadataLocationISO6709
        locationItem.value = "-03.731900-038.526700+004.000/" as NSString

        let parsedDate = await MediaMetadataService.creationDate(in: [dateItem])
        let parsedCoordinate = await MediaMetadataService.coordinate(in: [locationItem])
        let unrelatedDate = await MediaMetadataService.creationDate(in: [locationItem])
        let unrelatedCoordinate = await MediaMetadataService.coordinate(in: [dateItem])
        let date = try XCTUnwrap(parsedDate)
        let coordinate = try XCTUnwrap(parsedCoordinate)

        XCTAssertEqual(
            date,
            try Date("2026-08-20T18:30:00-03:00", strategy: .iso8601)
        )
        XCTAssertEqual(coordinate.latitude, -3.7319, accuracy: 0.000_001)
        XCTAssertEqual(coordinate.longitude, -38.5267, accuracy: 0.000_001)
        XCTAssertNil(unrelatedDate)
        XCTAssertNil(unrelatedCoordinate)
    }

    func testDurationFormatsCoverZeroNegativeRoundingAndHours() {
        XCTAssertEqual(TimeInterval.zero.shortDuration, "0:00")
        XCTAssertEqual(TimeInterval(-20).shortDuration, "0:00")
        XCTAssertEqual(TimeInterval(59.6).shortDuration, "1:00")
        XCTAssertEqual(TimeInterval(3_661).shortDuration, "61:01")

        XCTAssertEqual(TimeInterval.zero.spokenDuration, "0 segundos")
        XCTAssertEqual(TimeInterval(-20).spokenDuration, "0 segundos")
        XCTAssertEqual(TimeInterval(61).spokenDuration, "1 minuto e 1 segundo")
        XCTAssertEqual(TimeInterval(3_600).spokenDuration, "60 minutos")
    }

    func testImportedMovieCanAttachPhotoIdentifierAndRemoveItsLocalCopy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("treino.mov")
        try Data([0, 1, 2]).write(to: url)
        defer { try? FileManager.default.removeItem(at: root) }

        let movie = ImportedMovie(url: url, originalName: "Treino da manhã.mov")
            .attachingAssetIdentifier("photos-id")

        XCTAssertEqual(movie.url, url)
        XCTAssertEqual(movie.originalName, "Treino da manhã.mov")
        XCTAssertEqual(movie.assetIdentifier, "photos-id")

        movie.removeLocalCopy()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testImportedMovieMetadataEmptyHasNoSyntheticValues() {
        XCTAssertEqual(
            ImportedMovieMetadata.empty,
            ImportedMovieMetadata(duration: 0, capturedAt: nil, latitude: nil, longitude: nil)
        )
    }

    func testMediaPreflightErrorsRetainFileContext() {
        XCTAssertEqual(
            MediaPreflightError.missingVideo("treino.mov").errorDescription,
            "treino.mov não contém uma faixa de vídeo utilizável."
        )
        XCTAssertEqual(
            MediaPreflightError.missingAudio("treino.mov").errorDescription,
            "treino.mov não contém áudio. Escolha uma gravação com o som da quadra."
        )
        XCTAssertEqual(
            MediaPreflightError.videoTooLong("treino.mov", minutes: 30).errorDescription,
            "treino.mov tem mais de 30 minutos. Divida a gravação em partes menores antes de importar."
        )
    }

    @MainActor
    func testSessionMetadataPrefersVenueThenFallsBackToLocality() {
        let session = TennisSession(kind: .match, title: "Jogo", playedAt: .now)
        session.locationName = "Clube de Tênis"
        session.locality = "Fortaleza"
        XCTAssertEqual(session.displayLocation, "Clube de Tênis")

        session.locationName = ""
        XCTAssertEqual(session.displayLocation, "Fortaleza")

        session.locality = ""
        XCTAssertNil(session.displayLocation)
    }

    @MainActor
    func testSessionSearchMatchesAllEnrichedMetadata() {
        let session = TennisSession(
            kind: .practice,
            title: "Saques e voleios",
            opponent: "Marina",
            playedAt: .now
        )
        session.locationName = "Clube do Lago"
        session.locality = "Fortaleza"
        session.videos = [
            SessionVideo(
                order: 0,
                originalName: "treino.mov",
                relativePath: "sources/treino.mov",
                duration: 125
            ),
        ]

        XCTAssertTrue(session.matchesSearch("saques"))
        XCTAssertTrue(session.matchesSearch("MARINA"))
        XCTAssertTrue(session.matchesSearch("treino"))
        XCTAssertTrue(session.matchesSearch("clube do lago"))
        XCTAssertTrue(session.matchesSearch("fortaleza"))
        XCTAssertTrue(session.matchesSearch("2:05"))
        XCTAssertTrue(session.matchesSearch("2 minutos"))
        XCTAssertTrue(session.matchesSearch("   "))
        XCTAssertFalse(session.matchesSearch("Wimbledon"))
    }

    @MainActor
    func testCreatingSessionPersistsMetadataAndFeedsResolvedFactsToTitleGenerator() async throws {
        let defaults = UserDefaults.standard
        let previousStyle = defaults.object(forKey: "titleStyle")
        defaults.set(TitleStyle.standard.rawValue, forKey: "titleStyle")
        defer { restore(previousStyle, forKey: "titleStyle", in: defaults) }

        let fixture = try FeatureFixture()
        defer { fixture.remove() }
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = firstDate.addingTimeInterval(600)
        let firstMovie = try fixture.movie(named: "first.mov")
        let secondMovie = try fixture.movie(named: "second.mov")
        let titleGenerator = RecordingTitleGenerator(generatedTitle: "Manhã no Clube Azul")
        let locationResolver = RecordingLocationResolver(
            response: ResolvedSessionLocation(name: "Clube Azul", locality: "Fortaleza")
        )
        let model = AppModel(
            analyzer: FeatureStubAnalyzer(),
            storage: fixture.storage,
            locationResolver: locationResolver,
            titleGenerator: titleGenerator
        )
        let container = try makeContainer()

        let session = try model.createSession(
            kind: .practice,
            opponent: "Bia",
            movies: [firstMovie, secondMovie],
            metadata: [
                ImportedMovieMetadata(
                    duration: 120,
                    capturedAt: secondDate,
                    latitude: -3.72,
                    longitude: -38.50
                ),
                ImportedMovieMetadata(
                    duration: 180,
                    capturedAt: firstDate,
                    latitude: -3.74,
                    longitude: -38.54
                ),
            ],
            context: container.mainContext
        )

        try await waitUntil { session.metadataVersion == 1 && session.title == "Manhã no Clube Azul" }

        XCTAssertEqual(session.titleOrigin, .automatic)
        XCTAssertFalse(session.playedAtIsManual)
        XCTAssertEqual(session.playedAt, firstDate)
        XCTAssertEqual(session.recordedDuration, 300)
        XCTAssertEqual(session.sortedVideos.map(\.capturedAt), [secondDate, firstDate])
        XCTAssertEqual(session.displayLocation, "Clube Azul")
        XCTAssertEqual(try XCTUnwrap(session.latitude), -3.73, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(session.longitude), -38.52, accuracy: 0.000_001)
        XCTAssertEqual(locationResolver.requests.count, 1)
        XCTAssertEqual(try XCTUnwrap(titleGenerator.receivedFacts.last).location, "Clube Azul")
        XCTAssertEqual(titleGenerator.receivedFacts.last?.recordedDuration, 300)
        XCTAssertEqual(titleGenerator.receivedFacts.last?.recordingCount, 2)
        XCTAssertEqual(titleGenerator.receivedStyles, [.standard])
    }

    @MainActor
    func testAutomaticTitleUsesFallbackWhenGenerationIsUnavailable() async throws {
        let defaults = UserDefaults.standard
        let previousStyle = defaults.object(forKey: "titleStyle")
        defaults.set(TitleStyle.standard.rawValue, forKey: "titleStyle")
        defer { restore(previousStyle, forKey: "titleStyle", in: defaults) }

        let titleGenerator = RecordingTitleGenerator(generatedTitle: nil, fallbackTitle: "Título seguro")
        let session = TennisSession(
            kind: .practice,
            title: "Temporário",
            playedAt: .now,
            playedAtIsManual: false,
            titleOrigin: .automatic,
            status: .ready
        )
        let container = try makeContainer()
        container.mainContext.insert(session)
        let model = AppModel(
            analyzer: FeatureStubAnalyzer(),
            titleGenerator: titleGenerator
        )

        model.resumeIfNeeded([session], context: container.mainContext)
        try await waitUntil { session.metadataVersion == 1 && session.title == "Título seguro" }

        XCTAssertEqual(titleGenerator.generateCallCount, 1)
        XCTAssertEqual(session.titleOrigin, .automatic)
    }

    @MainActor
    func testCreativeTitleRunsAfterAnalysisAndReceivesRallyContext() async throws {
        let defaults = UserDefaults.standard
        let previousStyle = defaults.object(forKey: "titleStyle")
        defaults.set(TitleStyle.creative.rawValue, forKey: "titleStyle")
        defer { restore(previousStyle, forKey: "titleStyle", in: defaults) }

        let fixture = try FeatureFixture()
        defer { fixture.remove() }
        let movie = try fixture.movie(named: "creative.mov")
        let titleGenerator = RecordingTitleGenerator(
            generatedTitle: "Voleios sob as luzes",
            supportsVisualContext: true
        )
        let model = AppModel(
            analyzer: FeatureSuccessfulAnalyzer(),
            storage: fixture.storage,
            locationResolver: RecordingLocationResolver(response: nil),
            titleGenerator: titleGenerator
        )
        let container = try makeContainer()

        let session = try model.createSession(
            kind: .practice,
            opponent: "",
            movies: [movie],
            metadata: [
                ImportedMovieMetadata(
                    duration: 90,
                    capturedAt: .now,
                    latitude: -3.73,
                    longitude: -38.52
                ),
            ],
            context: container.mainContext
        )

        try await waitUntil {
            session.status == .reviewing && session.title == "Voleios sob as luzes"
        }

        XCTAssertEqual(session.clips.count, 1)
        XCTAssertEqual(titleGenerator.generateCallCount, 1)
        XCTAssertEqual(titleGenerator.receivedStyles, [.creative])
        XCTAssertEqual(titleGenerator.receivedFacts.last?.rallyCount, 1)
        XCTAssertEqual(titleGenerator.receivedVisualFrameCounts, [0])
    }

    @MainActor
    func testAddingRecordingRecomputesDurationDateAndRepresentativeLocation() async throws {
        let fixture = try FeatureFixture()
        defer { fixture.remove() }
        let container = try makeContainer()
        let later = Date(timeIntervalSince1970: 1_700_003_600)
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let session = TennisSession(
            kind: .practice,
            title: "Treino",
            playedAt: later,
            playedAtIsManual: false,
            titleOrigin: .manual,
            status: .ready
        )
        let existing = SessionVideo(
            order: 0,
            originalName: "existing.mov",
            relativePath: "sources/source-001.mov",
            duration: 120,
            capturedAt: later,
            latitude: -3.72,
            longitude: -38.50
        )
        session.videos = [existing]
        container.mainContext.insert(session)
        try fixture.storage.prepareSession(session.id)
        try Data([0]).write(to: fixture.storage.url(
            for: session.id,
            relativePath: existing.relativePath
        ))
        let addedMovie = try fixture.movie(named: "added.mov")
        let resolver = RecordingLocationResolver(
            response: ResolvedSessionLocation(name: "Clube recalculado", locality: "Fortaleza")
        )
        let model = AppModel(
            analyzer: FeatureStubAnalyzer(),
            storage: fixture.storage,
            locationResolver: resolver
        )

        try model.addRecordings(
            [addedMovie],
            metadata: [
                ImportedMovieMetadata(
                    duration: 180,
                    capturedAt: earlier,
                    latitude: -3.74,
                    longitude: -38.54
                ),
            ],
            to: session,
            context: container.mainContext
        )

        try await waitUntil { session.metadataVersion == 1 }

        XCTAssertEqual(session.sortedVideos.count, 2)
        XCTAssertEqual(session.sortedVideos.map(\.order), [0, 1])
        XCTAssertEqual(session.recordedDuration, 300)
        XCTAssertEqual(session.playedAt, earlier)
        XCTAssertEqual(try XCTUnwrap(session.latitude), -3.73, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(session.longitude), -38.52, accuracy: 0.000_001)
        XCTAssertEqual(session.displayLocation, "Clube recalculado")
        XCTAssertEqual(resolver.requests.count, 1)
    }

    @MainActor
    func testEnrichmentNeverOverwritesManualTitleOrManualDate() async throws {
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let session = TennisSession(
            kind: .match,
            title: "Final do clube",
            playedAt: originalDate,
            playedAtIsManual: true,
            titleOrigin: .manual,
            status: .ready
        )
        session.videos = [
            SessionVideo(
                order: 0,
                originalName: "jogo.mov",
                relativePath: "sources/jogo.mov",
                duration: 100,
                capturedAt: originalDate.addingTimeInterval(-86_400),
                latitude: -3.73,
                longitude: -38.52
            ),
        ]
        let container = try makeContainer()
        container.mainContext.insert(session)
        let titleGenerator = RecordingTitleGenerator(generatedTitle: "Não deveria aparecer")
        let model = AppModel(
            analyzer: FeatureStubAnalyzer(),
            locationResolver: RecordingLocationResolver(
                response: ResolvedSessionLocation(name: "Clube", locality: nil)
            ),
            titleGenerator: titleGenerator
        )

        model.resumeIfNeeded([session], context: container.mainContext)
        try await waitUntil { session.metadataVersion == 1 }

        XCTAssertEqual(session.title, "Final do clube")
        XCTAssertEqual(session.playedAt, originalDate)
        XCTAssertEqual(titleGenerator.generateCallCount, 0)
    }

    @MainActor
    func testLegacyTitlesAreClassifiedBeforeAutomaticEnrichment() async throws {
        let container = try makeContainer()
        let manual = TennisSession(
            kind: .match,
            title: "Título antigo",
            playedAt: .now,
            titleOrigin: .legacy,
            status: .ready
        )
        let automatic = TennisSession(
            kind: .practice,
            title: "  ",
            playedAt: .now,
            titleOrigin: .legacy,
            status: .ready
        )
        container.mainContext.insert(manual)
        container.mainContext.insert(automatic)
        let titleGenerator = RecordingTitleGenerator(generatedTitle: "Título migrado")
        let model = AppModel(
            analyzer: FeatureStubAnalyzer(),
            titleGenerator: titleGenerator
        )

        model.resumeIfNeeded([manual, automatic], context: container.mainContext)
        try await waitUntil { manual.metadataVersion == 1 && automatic.metadataVersion == 1 }

        XCTAssertEqual(manual.titleOrigin, .manual)
        XCTAssertEqual(manual.title, "Título antigo")
        XCTAssertEqual(automatic.titleOrigin, .automatic)
        XCTAssertEqual(automatic.title, "Título migrado")
        XCTAssertEqual(titleGenerator.generateCallCount, 1)
    }

    @MainActor
    func testEnrichmentClearsStaleLocationWhenNoRecordingHasCoordinates() async throws {
        let session = TennisSession(
            kind: .practice,
            title: "Sem GPS",
            playedAt: .now,
            titleOrigin: .manual,
            status: .ready
        )
        session.latitude = -3.73
        session.longitude = -38.52
        session.locationName = "Local antigo"
        session.locality = "Fortaleza"
        let container = try makeContainer()
        container.mainContext.insert(session)
        let model = AppModel(analyzer: FeatureStubAnalyzer())

        model.resumeIfNeeded([session], context: container.mainContext)
        try await waitUntil { session.metadataVersion == 1 }

        XCTAssertNil(session.latitude)
        XCTAssertNil(session.longitude)
        XCTAssertNil(session.locationName)
        XCTAssertNil(session.locality)
    }

    @MainActor
    func testResumeRetriesUnresolvedLocationForAlreadyEnrichedSession() async throws {
        let session = TennisSession(
            kind: .practice,
            title: "Treino",
            playedAt: .now,
            titleOrigin: .manual,
            status: .ready
        )
        session.metadataVersion = 1
        session.latitude = -3.73
        session.longitude = -38.52
        session.videos = [
            SessionVideo(
                order: 0,
                originalName: "treino.mov",
                relativePath: "sources/treino.mov",
                duration: 90,
                capturedAt: .now,
                latitude: -3.73,
                longitude: -38.52
            ),
        ]
        let container = try makeContainer()
        container.mainContext.insert(session)
        let resolver = RecordingLocationResolver(
            response: ResolvedSessionLocation(name: nil, locality: "Fortaleza")
        )
        let model = AppModel(
            analyzer: FeatureStubAnalyzer(),
            locationResolver: resolver
        )

        model.resumeIfNeeded([session], context: container.mainContext)
        try await waitUntil { session.displayLocation == "Fortaleza" }

        XCTAssertEqual(resolver.requests.count, 1)
        XCTAssertEqual(session.metadataVersion, 1)
    }

    func testVisualContextProviderIgnoresUnreadableFrames() async {
        let provider = SessionVisualContextProvider()
        let frames = await provider.frames(for: [
            SessionVisualFrameRequest(
                videoURL: URL(fileURLWithPath: "/arquivo/inexistente.mov"),
                time: 4
            ),
        ])

        XCTAssertTrue(frames.isEmpty)
    }

    @MainActor
    func testFoundationModelGeneratorFailsSafelyWhenModelIsUnavailable() async throws {
        let generator = SessionTitleGenerator()
        _ = generator.supportsVisualContext
        let result = await generator.generate(
            for: try facts(atHour: 19, location: "Clube Azul"),
            style: .standard,
            visualFrames: []
        )

        if let result {
            XCTAssertEqual(SessionTitleGenerator.validated(result), result)
        }
    }

    private func facts(atHour hour: Int, location: String? = nil) throws -> SessionTitleFacts {
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 20,
            hour: hour
        )))
        return SessionTitleFacts(
            kind: .practice,
            playedAt: date,
            recordedDuration: 120,
            opponent: "",
            location: location,
            recordingCount: 1,
            rallyCount: 0
        )
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: TennisSession.self,
            SessionVideo.self,
            RallyClip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "A condição assíncrona não foi atendida dentro do prazo.")
    }

    private func restore(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

nonisolated private struct FeatureStubAnalyzer: TennisAnalyzing {
    func analyze(
        videoAt url: URL,
        progress: @escaping @MainActor @Sendable (ProcessingUpdate) -> Void
    ) async throws -> VideoAnalysis {
        throw ProcessingError.noImpacts
    }
}

@MainActor
private final class RecordingTitleGenerator: SessionTitleGenerating {
    let supportsVisualContext: Bool
    private let generatedTitle: String?
    private let fallbackTitle: String
    private(set) var receivedFacts: [SessionTitleFacts] = []
    private(set) var receivedStyles: [TitleStyle] = []
    private(set) var receivedVisualFrameCounts: [Int] = []
    private(set) var generateCallCount = 0

    init(
        generatedTitle: String?,
        fallbackTitle: String = "Título inicial",
        supportsVisualContext: Bool = false
    ) {
        self.generatedTitle = generatedTitle
        self.fallbackTitle = fallbackTitle
        self.supportsVisualContext = supportsVisualContext
    }

    func fallback(for facts: SessionTitleFacts, style: TitleStyle) -> String {
        fallbackTitle
    }

    func generate(
        for facts: SessionTitleFacts,
        style: TitleStyle,
        visualFrames: [CGImage]
    ) async -> String? {
        generateCallCount += 1
        receivedFacts.append(facts)
        receivedStyles.append(style)
        receivedVisualFrameCounts.append(visualFrames.count)
        return generatedTitle
    }
}

nonisolated private struct FeatureSuccessfulAnalyzer: TennisAnalyzing {
    func analyze(
        videoAt url: URL,
        progress: @escaping @MainActor @Sendable (ProcessingUpdate) -> Void
    ) async throws -> VideoAnalysis {
        let impact = ImpactEvent(
            time: 4,
            score: 0.9,
            amplitude: 1,
            midEnergyRatio: 0.2,
            highEnergyRatio: 0.1
        )
        return VideoAnalysis(
            duration: 90,
            impacts: [impact],
            clips: [ClipRange(start: 2, end: 7)]
        )
    }
}

@MainActor
private final class RecordingLocationResolver: SessionLocationResolving {
    struct Request: Equatable {
        let latitude: Double
        let longitude: Double
    }

    private let response: ResolvedSessionLocation?
    private(set) var requests: [Request] = []

    init(response: ResolvedSessionLocation?) {
        self.response = response
    }

    func resolve(latitude: Double, longitude: Double) async -> ResolvedSessionLocation? {
        requests.append(Request(latitude: latitude, longitude: longitude))
        return response
    }
}

private final class FeatureFixture {
    let root: URL
    let storage: SessionStorage

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        storage = SessionStorage(rootURL: root.appendingPathComponent("sessions", isDirectory: true))
    }

    func movie(named name: String) throws -> ImportedMovie {
        let url = root.appendingPathComponent(name)
        try Data([0, 1, 2]).write(to: url)
        return ImportedMovie(url: url, originalName: name)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
