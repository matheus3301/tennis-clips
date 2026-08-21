import CoreGraphics
import Foundation
import Observation
import SwiftData
import TennisClipsCore

nonisolated enum SessionEditingError: LocalizedError {
    case processingInProgress
    case recordingLimit
    case lastRecording

    var errorDescription: String? {
        switch self {
        case .processingInProgress:
            "Espere o processamento terminar antes de alterar as gravações."
        case .recordingLimit:
            "Cada sessão pode ter no máximo 8 gravações."
        case .lastRecording:
            "Uma sessão precisa manter pelo menos uma gravação."
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private let analyzer: any TennisAnalyzing
    private let editor: RallyVideoEditor
    private let storage: SessionStorage
    private let photoExporter: PhotoLibraryExporter
    private let activityController: ProcessingActivityController
    private let continuedProcessing: ContinuedProcessingService
    private let mediaPreflight: MediaPreflightService
    private let metadataService: MediaMetadataService
    private let locationResolver: any SessionLocationResolving
    private let titleGenerator: any SessionTitleGenerating
    private let visualContextProvider: SessionVisualContextProvider

    @ObservationIgnored private var activeTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var activeRequestIDs: [UUID: UUID] = [:]
    @ObservationIgnored private var enrichmentTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var enrichmentRequestIDs: [UUID: UUID] = [:]

    var notice: AppNotice?
    var savingClipID: UUID?

    init(
        analyzer: any TennisAnalyzing = OnDeviceTennisProcessor(),
        editor: RallyVideoEditor = RallyVideoEditor(),
        storage: SessionStorage = SessionStorage(),
        photoExporter: PhotoLibraryExporter = PhotoLibraryExporter(),
        activityController: ProcessingActivityController = ProcessingActivityController(),
        continuedProcessing: ContinuedProcessingService = ContinuedProcessingService(),
        mediaPreflight: MediaPreflightService = MediaPreflightService(),
        metadataService: MediaMetadataService = MediaMetadataService(),
        locationResolver: any SessionLocationResolving = SessionLocationResolver(),
        titleGenerator: any SessionTitleGenerating = SessionTitleGenerator(),
        visualContextProvider: SessionVisualContextProvider = SessionVisualContextProvider()
    ) {
        self.analyzer = analyzer
        self.editor = editor
        self.storage = storage
        self.photoExporter = photoExporter
        self.activityController = activityController
        self.continuedProcessing = continuedProcessing
        self.mediaPreflight = mediaPreflight
        self.metadataService = metadataService
        self.locationResolver = locationResolver
        self.titleGenerator = titleGenerator
        self.visualContextProvider = visualContextProvider
    }

    func validateImports(_ movies: [ImportedMovie]) async throws -> [ImportedMovieMetadata] {
        try await mediaPreflight.validate(movies)
    }

    func createSession(
        kind: SessionKind,
        opponent: String,
        movies: [ImportedMovie],
        metadata: [ImportedMovieMetadata],
        context: ModelContext
    ) throws -> TennisSession {
        let playedAt = metadata.compactMap(\.capturedAt).min() ?? .now
        let session = TennisSession(
            kind: kind,
            title: "",
            opponent: opponent.trimmingCharacters(in: .whitespacesAndNewlines),
            playedAt: playedAt,
            playedAtIsManual: false,
            titleOrigin: .automatic,
            automaticTitleState: .pending
        )
        return try persistSession(
            session,
            movies: movies,
            metadata: metadata,
            context: context
        )
    }

    func createSession(
        kind: SessionKind,
        title: String,
        opponent: String,
        playedAt: Date,
        movies: [ImportedMovie],
        context: ModelContext
    ) throws -> TennisSession {
        let session = TennisSession(
            kind: kind,
            title: title,
            opponent: opponent,
            playedAt: playedAt,
            titleOrigin: .manual
        )
        return try persistSession(session, movies: movies, metadata: [], context: context)
    }

    private func persistSession(
        _ session: TennisSession,
        movies: [ImportedMovie],
        metadata: [ImportedMovieMetadata],
        context: ModelContext
    ) throws -> TennisSession {
        context.insert(session)
        do {
            try storage.prepareSession(session.id)
            try storage.validateCapacity(for: movies)
            for (index, movie) in movies.enumerated() {
                let relativePath = try storage.persist(movie, sessionID: session.id, order: index)
                let videoMetadata = metadata.indices.contains(index) ? metadata[index] : nil
                session.videos.append(SessionVideo(
                    order: index,
                    originalName: movie.originalName,
                    relativePath: relativePath,
                    duration: videoMetadata?.duration ?? 0,
                    capturedAt: videoMetadata?.capturedAt,
                    latitude: videoMetadata?.latitude,
                    longitude: videoMetadata?.longitude
                ))
            }
            try context.save()
            startAnalysis(session, context: context)
            startEnrichment(session, context: context)
            return session
        } catch {
            storage.removeSession(session.id)
            context.delete(session)
            throw error
        }
    }

    func addRecordings(
        _ movies: [ImportedMovie],
        metadata: [ImportedMovieMetadata] = [],
        to session: TennisSession,
        context: ModelContext
    ) throws {
        guard !isBusy(session) else { throw SessionEditingError.processingInProgress }
        guard session.videos.count + movies.count <= 8 else {
            throw SessionEditingError.recordingLimit
        }
        try storage.validateCapacity(for: movies)

        var persistedPaths: [String] = []
        var newVideos: [SessionVideo] = []
        do {
            let firstOrder = (session.sortedVideos.last?.order ?? -1) + 1
            for (offset, movie) in movies.enumerated() {
                let relativePath = try storage.persist(
                    movie,
                    sessionID: session.id,
                    order: firstOrder + offset
                )
                persistedPaths.append(relativePath)
                let videoMetadata = metadata.indices.contains(offset) ? metadata[offset] : nil
                let video = SessionVideo(
                    order: firstOrder + offset,
                    originalName: movie.originalName,
                    relativePath: relativePath,
                    duration: videoMetadata?.duration ?? 0,
                    capturedAt: videoMetadata?.capturedAt,
                    latitude: videoMetadata?.latitude,
                    longitude: videoMetadata?.longitude
                )
                newVideos.append(video)
                session.videos.append(video)
            }
            session.outputPath = nil
            try context.save()
            storage.removeCompilation(sessionID: session.id)
            notice = .success(AppCopy.importedRecordings(movies.count) + ". Reanalisando a sessão.")
            startAnalysis(session, context: context)
            startEnrichment(session, context: context, force: true)
        } catch {
            context.rollback()
            for path in persistedPaths {
                storage.removeFile(sessionID: session.id, relativePath: path)
            }
            for video in newVideos {
                session.videos.removeAll { $0.id == video.id }
            }
            throw error
        }
    }

    func removeRecording(
        _ video: SessionVideo,
        from session: TennisSession,
        context: ModelContext
    ) throws {
        guard !isBusy(session) else { throw SessionEditingError.processingInProgress }
        guard session.videos.count > 1 else { throw SessionEditingError.lastRecording }

        let stagedURL = try storage.stageFileRemoval(
            sessionID: session.id,
            relativePath: video.relativePath
        )
        do {
            for clip in session.clips where clip.sourceVideoID == video.id {
                context.delete(clip)
            }
            session.clips.removeAll { $0.sourceVideoID == video.id }
            session.videos.removeAll { $0.id == video.id }
            context.delete(video)
            for (order, existing) in session.sortedVideos.enumerated() {
                existing.order = order
            }
            session.outputPath = nil
            try context.save()
            storage.finalizeStagedRemoval(stagedURL)
            storage.removeCompilation(sessionID: session.id)
            notice = .success("Gravação removida. Reanalisando a sessão.")
            startAnalysis(session, context: context)
            startEnrichment(session, context: context, force: true)
        } catch {
            context.rollback()
            if let stagedURL {
                try? storage.restoreStagedFileRemoval(
                    stagedURL,
                    sessionID: session.id,
                    relativePath: video.relativePath
                )
            }
            throw error
        }
    }

    @discardableResult
    func startAnalysis(_ session: TennisSession, context: ModelContext) -> Bool {
        guard activeTasks[session.id] == nil else { return false }
        let requestID = UUID()
        activeRequestIDs[session.id] = requestID
        session.status = .analyzing
        session.progress = 0
        session.progressLabel = "Preparando gravações"
        session.errorMessage = nil

        activeTasks[session.id] = Task { [weak self] in
            guard let self else { return }
            await self.continuedProcessing.perform(
                sessionID: session.id,
                operationName: "analysis",
                attemptID: requestID,
                title: "Encontrando jogadas",
                subtitle: session.displayTitle
            ) { progress in
                await self.runAnalysis(
                    session,
                    requestID: requestID,
                    context: context,
                    systemProgress: progress
                )
            }
        }
        return true
    }

    func resumeIfNeeded(_ sessions: [TennisSession], context: ModelContext) {
        for session in sessions where activeTasks[session.id] == nil {
            if session.metadataVersion < 1
                || (session.latitude != nil && session.displayLocation == nil)
                || shouldResumeAutomaticTitle(for: session) {
                startEnrichment(session, context: context)
            }
            switch session.status {
            case .analyzing:
                startAnalysis(session, context: context)
            case .exporting:
                compile(session, context: context)
            default:
                break
            }
        }
    }

    func decide(
        _ decision: RallyDecision,
        for clip: RallyClip,
        in session: TennisSession,
        context: ModelContext
    ) {
        clip.decision = decision
        session.status = session.pendingClipCount == 0 ? .ready : .reviewing
        save(context, failureMessage: "Não foi possível salvar essa escolha.")
    }

    func resetDecision(
        for clip: RallyClip,
        in session: TennisSession,
        context: ModelContext
    ) {
        clip.decision = .pending
        session.status = .reviewing
        save(context, failureMessage: "Não foi possível desfazer essa escolha.")
    }

    func updateClipBounds(
        _ clip: RallyClip,
        start: TimeInterval,
        end: TimeInterval,
        in session: TennisSession,
        context: ModelContext
    ) -> Bool {
        guard start >= 0, end - start >= 0.5 else {
            notice = .warning("A jogada precisa ter pelo menos meio segundo.")
            return false
        }
        clip.start = start
        clip.end = end
        session.status = session.pendingClipCount == 0 ? .ready : .reviewing
        return save(context, failureMessage: "Não foi possível salvar o novo corte.")
    }

    func splitClip(
        _ clip: RallyClip,
        in session: TennisSession,
        context: ModelContext
    ) -> Bool {
        guard clip.duration >= 2 else {
            notice = .warning("O corte é curto demais para ser dividido.")
            return false
        }
        let midpoint = clip.start + clip.duration / 2
        let originalEnd = clip.end
        let originalImpactCount = clip.impactCount
        let secondImpactCount = originalImpactCount / 2
        clip.end = midpoint
        clip.impactCount = originalImpactCount - secondImpactCount
        for existing in session.clips where existing.order > clip.order {
            existing.order += 1
        }
        let secondClip = RallyClip(
            sourceVideoID: clip.sourceVideoID,
            order: clip.order + 1,
            start: midpoint,
            end: originalEnd,
            impactCount: secondImpactCount,
            confidence: clip.confidence,
            decision: clip.decision
        )
        context.insert(secondClip)
        session.clips.append(secondClip)
        session.status = session.pendingClipCount == 0 ? .ready : .reviewing
        return save(context, failureMessage: "Não foi possível dividir a jogada.")
    }

    func mergeWithNextClip(
        _ clip: RallyClip,
        in session: TennisSession,
        context: ModelContext
    ) -> Bool {
        let clips = session.sortedClips
        guard let index = clips.firstIndex(where: { $0.id == clip.id }),
              clips.indices.contains(index + 1),
              clips[index + 1].sourceVideoID == clip.sourceVideoID
        else {
            notice = .warning("Não há uma jogada seguinte da mesma gravação para unir.")
            return false
        }
        let next = clips[index + 1]
        guard next.decision == clip.decision else {
            notice = .warning("Para unir, coloque as duas jogadas no mesmo grupo primeiro.")
            return false
        }
        clip.end = max(clip.end, next.end)
        clip.impactCount += next.impactCount
        clip.confidence = (clip.confidence + next.confidence) / 2
        session.clips.removeAll { $0.id == next.id }
        context.delete(next)
        for (order, existing) in session.sortedClips.enumerated() {
            existing.order = order
        }
        session.status = session.pendingClipCount == 0 ? .ready : .reviewing
        return save(context, failureMessage: "Não foi possível unir as jogadas.")
    }

    @discardableResult
    func compile(_ session: TennisSession, context: ModelContext) -> Bool {
        guard !session.keptClips.isEmpty else {
            notice = .warning("Inclua pelo menos uma jogada antes de montar o vídeo.")
            return false
        }
        guard activeTasks[session.id] == nil else { return false }
        let requestID = UUID()
        activeRequestIDs[session.id] = requestID
        session.status = .exporting
        session.progress = 0
        session.progressLabel = "Montando seu vídeo"
        session.errorMessage = nil
        let exportQuality = ExportQuality.current

        activeTasks[session.id] = Task { [weak self] in
            guard let self else { return }
            await self.continuedProcessing.perform(
                sessionID: session.id,
                operationName: "export",
                attemptID: requestID,
                title: "Montando seu vídeo",
                subtitle: session.displayTitle
            ) { progress in
                await self.runCompilation(
                    session,
                    requestID: requestID,
                    context: context,
                    systemProgress: progress,
                    exportQuality: exportQuality
                )
            }
        }
        return true
    }

    func saveClip(
        _ clip: RallyClip,
        from session: TennisSession,
        context: ModelContext
    ) async {
        guard savingClipID == nil, let segment = segment(for: clip, in: session) else { return }
        savingClipID = clip.id
        defer { savingClipID = nil }
        let relativePath = storage.clipRelativePath(clip.id)
        let outputURL = storage.url(for: session.id, relativePath: relativePath)
        do {
            try await editor.export(segment: segment, to: outputURL)
            try await photoExporter.saveVideo(at: outputURL)
            clip.savedToPhotos = true
            try context.save()
            notice = .success("Jogada salva nas Fotos.")
        } catch {
            notice = .error(error.localizedDescription)
        }
    }

    func saveCompilation(_ session: TennisSession) async {
        guard let outputURL = outputURL(for: session) else { return }
        do {
            try await photoExporter.saveVideo(at: outputURL)
            notice = .success("Vídeo salvo nas Fotos.")
        } catch {
            notice = .error(error.localizedDescription)
        }
    }

    func delete(_ session: TennisSession, context: ModelContext) {
        cancelTask(for: session.id)
        enrichmentTasks[session.id]?.cancel()
        enrichmentTasks[session.id] = nil
        enrichmentRequestIDs[session.id] = nil
        do {
            let stagedURL = try storage.stageRemoval(session.id)
            context.delete(session)
            do {
                try context.save()
                storage.finalizeStagedRemoval(stagedURL)
            } catch {
                context.rollback()
                if let stagedURL {
                    try? storage.restoreStagedRemoval(stagedURL, sessionID: session.id)
                }
                notice = .error("Não foi possível remover a sessão. Nada foi apagado.")
            }
        } catch {
            notice = .error("Não foi possível preparar a remoção dos vídeos.")
        }
    }

    func storageUsageBytes() async -> Int64 {
        let storage = storage
        return await Task.detached(priority: .utility) {
            storage.storageUsageBytes()
        }.value
    }

    func updateSession(
        _ session: TennisSession,
        kind: SessionKind,
        title: String,
        opponent: String,
        playedAt: Date,
        context: ModelContext
    ) -> Bool {
        session.kind = kind
        session.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        session.titleOrigin = .manual
        session.automaticTitleState = .notApplicable
        session.opponent = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        session.playedAt = playedAt
        session.playedAtIsManual = true
        session.updatedAt = .now
        return save(context, failureMessage: "Não foi possível atualizar a sessão.")
    }

    func retryAutomaticTitle(for session: TennisSession, context: ModelContext) {
        guard session.titleOrigin == .automatic,
              session.automaticTitleState.canRetry else {
            return
        }
        startEnrichment(session, context: context, force: true)
    }

    func cancelProcessing(_ session: TennisSession, context: ModelContext) {
        guard isBusy(session) else { return }
        cancelTask(for: session.id)
        session.status = .failed
        session.progressLabel = "Processamento interrompido"
        session.errorMessage = "O processamento foi interrompido. Você pode tentar novamente quando quiser."
        save(context, failureMessage: "Não foi possível registrar a interrupção.")
    }

    func sourceURL(for clip: RallyClip, in session: TennisSession) -> URL? {
        guard let video = session.videos.first(where: { $0.id == clip.sourceVideoID }) else {
            return nil
        }
        return storage.url(for: session.id, relativePath: video.relativePath)
    }

    func coverURL(for session: TennisSession) -> URL? {
        guard let video = session.sortedVideos.first else { return nil }
        return storage.url(for: session.id, relativePath: video.relativePath)
    }

    func outputURL(for session: TennisSession) -> URL? {
        guard let outputPath = session.outputPath else { return nil }
        return storage.url(for: session.id, relativePath: outputPath)
    }

    func clipOutputURL(for clip: RallyClip, in session: TennisSession) -> URL? {
        guard clip.savedToPhotos else { return nil }
        return storage.url(
            for: session.id,
            relativePath: storage.clipRelativePath(clip.id)
        )
    }

    func isBusy(_ session: TennisSession) -> Bool {
        activeTasks[session.id] != nil
    }

    private func runAnalysis(
        _ session: TennisSession,
        requestID: UUID,
        context: ModelContext,
        systemProgress: Progress?
    ) async {
        let totalVideos = max(session.videos.count, 1)
        await activityController.start(
            sessionID: session.id,
            title: session.displayTitle,
            stage: "Preparando gravações",
            totalVideos: totalVideos
        )
        do {
            for clip in session.clips { context.delete(clip) }
            session.clips.removeAll()
            var clipOrder = 0
            var failedVideoNames: [String] = []
            for (videoIndex, video) in session.sortedVideos.enumerated() {
                try Task.checkCancellation()
                guard activeRequestIDs[session.id] == requestID else { return }
                let url = storage.url(for: session.id, relativePath: video.relativePath)
                let analysis: VideoAnalysis
                do {
                    analysis = try await analyzer.analyze(videoAt: url) { [weak self] update in
                        guard let self, self.activeRequestIDs[session.id] == requestID else { return }
                        let overall = (Double(videoIndex) + update.fraction) / Double(totalVideos)
                        let label = Self.label(for: update.stage)
                        session.progress = overall
                        session.progressLabel = label
                        systemProgress?.completedUnitCount = Int64(overall * 1_000)
                        Task {
                            await self.activityController.update(
                                sessionID: session.id,
                                progress: overall,
                                stage: label,
                                currentVideo: videoIndex + 1,
                                totalVideos: totalVideos
                            )
                        }
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failedVideoNames.append(video.originalName)
                    let overall = Double(videoIndex + 1) / Double(totalVideos)
                    session.progress = overall
                    session.progressLabel = "Seguindo para a próxima gravação"
                    systemProgress?.completedUnitCount = Int64(overall * 1_000)
                    continue
                }
                video.duration = analysis.duration
                for range in analysis.clips {
                    let events = analysis.impacts.filter { range.start <= $0.time && $0.time <= range.end }
                    let confidence = events.isEmpty
                        ? 0
                        : events.reduce(0) { $0 + $1.score } / Double(events.count)
                    session.clips.append(RallyClip(
                        sourceVideoID: video.id,
                        order: clipOrder,
                        start: range.start,
                        end: range.end,
                        impactCount: events.count,
                        confidence: confidence
                    ))
                    clipOrder += 1
                }
                try context.save()
            }
            guard !session.clips.isEmpty else { throw ProcessingError.noImpacts }
            session.progress = 1
            systemProgress?.completedUnitCount = 1_000
            session.progressLabel = AppCopy.plays(session.clips.count)
                + (session.clips.count == 1 ? " pronta" : " prontas")
            session.status = .reviewing
            session.errorMessage = Self.partialAnalysisMessage(
                failedVideoNames: failedVideoNames,
                totalVideoCount: totalVideos
            )
            try context.save()
            if TitleStyle.current == .creative, session.titleOrigin == .automatic {
                if let enrichmentTask = enrichmentTasks[session.id] {
                    await enrichmentTask.value
                }
                await refreshAutomaticTitle(for: session, context: context)
            }
            await activityController.end(
                sessionID: session.id,
                finalStage: "Jogadas prontas para revisar",
                success: true
            )
        } catch is CancellationError {
            await activityController.end(
                sessionID: session.id,
                finalStage: "Processamento interrompido",
                success: false
            )
        } catch {
            guard activeRequestIDs[session.id] == requestID else { return }
            session.status = .failed
            session.errorMessage = error.localizedDescription
            session.progressLabel = "Não foi possível encontrar as jogadas"
            save(
                context,
                failureMessage: "Não foi possível registrar a falha da análise."
            )
            await activityController.end(
                sessionID: session.id,
                finalStage: "Processamento interrompido",
                success: false
            )
        }
        finishTask(for: session.id, requestID: requestID)
    }

    private func runCompilation(
        _ session: TennisSession,
        requestID: UUID,
        context: ModelContext,
        systemProgress: Progress?,
        exportQuality: ExportQuality
    ) async {
        await activityController.start(
            sessionID: session.id,
            title: session.displayTitle,
            stage: "Montando seu vídeo",
            totalVideos: 1
        )
        do {
            let segments = session.keptClips.compactMap { segment(for: $0, in: session) }
            let relativePath = storage.compilationRelativePath()
            let destination = storage.url(for: session.id, relativePath: relativePath)
            session.progress = 0.12
            systemProgress?.completedUnitCount = 120
            await activityController.update(
                sessionID: session.id,
                progress: 0.12,
                stage: "Montando seu vídeo",
                currentVideo: 1,
                totalVideos: 1
            )
            try await editor.export(
                segments: segments,
                to: destination,
                quality: exportQuality
            ) { [weak self] fraction in
                guard let self, self.activeRequestIDs[session.id] == requestID else { return }
                let overall = 0.12 + (fraction * 0.86)
                let visibleProgress = max(session.progress, overall)
                session.progress = visibleProgress
                session.progressLabel = Self.compilationLabel(for: visibleProgress)
                systemProgress?.completedUnitCount = Int64(visibleProgress * 1_000)
                Task {
                    await self.activityController.update(
                        sessionID: session.id,
                        progress: visibleProgress,
                        stage: session.progressLabel,
                        currentVideo: 1,
                        totalVideos: 1
                    )
                }
            }
            guard activeRequestIDs[session.id] == requestID else { return }
            session.outputPath = relativePath
            session.progress = 1
            systemProgress?.completedUnitCount = 1_000
            session.progressLabel = "Vídeo pronto"
            session.status = .completed
            try context.save()
            await activityController.end(
                sessionID: session.id,
                finalStage: "Seu vídeo está pronto",
                success: true
            )
        } catch is CancellationError {
            await activityController.end(
                sessionID: session.id,
                finalStage: "Exportação interrompida",
                success: false
            )
        } catch {
            guard activeRequestIDs[session.id] == requestID else { return }
            session.status = .failed
            session.errorMessage = error.localizedDescription
            session.progressLabel = "Não foi possível montar o vídeo"
            save(
                context,
                failureMessage: "Não foi possível registrar a falha da exportação."
            )
            await activityController.end(
                sessionID: session.id,
                finalStage: "Exportação interrompida",
                success: false
            )
        }
        finishTask(for: session.id, requestID: requestID)
    }

    private func segment(for clip: RallyClip, in session: TennisSession) -> CompilationSegment? {
        guard let sourceURL = sourceURL(for: clip, in: session) else { return nil }
        return CompilationSegment(sourceURL: sourceURL, start: clip.start, end: clip.end)
    }

    private func cancelTask(for sessionID: UUID) {
        activeTasks[sessionID]?.cancel()
        activeTasks[sessionID] = nil
        activeRequestIDs[sessionID] = nil
    }

    private func startEnrichment(
        _ session: TennisSession,
        context: ModelContext,
        force: Bool = false
    ) {
        if force {
            enrichmentTasks[session.id]?.cancel()
            enrichmentTasks[session.id] = nil
            enrichmentRequestIDs[session.id] = nil
            session.metadataVersion = 0
            if session.titleOrigin == .automatic {
                session.title = ""
                session.automaticTitleState = .pending
            }
        } else {
            guard enrichmentTasks[session.id] == nil else { return }
        }
        let requestID = UUID()
        enrichmentRequestIDs[session.id] = requestID
        enrichmentTasks[session.id] = Task { [weak self] in
            guard let self else { return }
            await self.enrich(session, requestID: requestID, context: context)
            self.finishEnrichment(for: session.id, requestID: requestID)
        }
    }

    private func enrich(
        _ session: TennisSession,
        requestID: UUID,
        context: ModelContext
    ) async {
        guard isActiveEnrichment(for: session.id, requestID: requestID) else { return }
        if session.titleOrigin == .legacy {
            if session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.titleOrigin = .automatic
                session.automaticTitleState = .pending
            } else {
                session.titleOrigin = .manual
                session.automaticTitleState = .notApplicable
            }
        } else if session.titleOrigin == .automatic,
                  session.automaticTitleState == .legacy {
            session.title = ""
            session.automaticTitleState = .pending
        }

        for video in session.sortedVideos
        where video.capturedAt == nil || video.duration <= 0
            || video.latitude == nil || video.longitude == nil {
            guard !Task.isCancelled else { return }
            let movie = ImportedMovie(
                url: storage.url(for: session.id, relativePath: video.relativePath),
                originalName: video.originalName
            )
            guard let metadata = try? await metadataService.metadata(for: movie) else { continue }
            guard isActiveEnrichment(for: session.id, requestID: requestID) else { return }
            if video.duration <= 0 { video.duration = metadata.duration }
            if video.capturedAt == nil { video.capturedAt = metadata.capturedAt }
            if video.latitude == nil { video.latitude = metadata.latitude }
            if video.longitude == nil { video.longitude = metadata.longitude }
        }

        if !session.playedAtIsManual,
           let capturedAt = session.videos.compactMap(\.capturedAt).min() {
            session.playedAt = capturedAt
        }
        if let coordinate = representativeCoordinate(for: session) {
            let latitudeChanged = session.latitude.map {
                abs($0 - coordinate.latitude) > 0.000_01
            } ?? true
            let longitudeChanged = session.longitude.map {
                abs($0 - coordinate.longitude) > 0.000_01
            } ?? true
            let coordinateChanged = latitudeChanged || longitudeChanged
            if coordinateChanged {
                session.locationName = nil
                session.locality = nil
            }
            session.latitude = coordinate.latitude
            session.longitude = coordinate.longitude
            if let location = await locationResolver.resolve(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ) {
                guard isActiveEnrichment(for: session.id, requestID: requestID) else { return }
                session.locationName = location.name
                session.locality = location.locality
            }
        } else {
            session.latitude = nil
            session.longitude = nil
            session.locationName = nil
            session.locality = nil
        }
        guard isActiveEnrichment(for: session.id, requestID: requestID) else { return }
        session.metadataVersion = 1
        guard save(context, failureMessage: "Não foi possível salvar os metadados da sessão.") else {
            session.metadataVersion = 0
            return
        }

        if session.titleOrigin == .automatic,
           TitleStyle.current == .standard || session.status != .analyzing {
            await refreshAutomaticTitle(for: session, context: context)
        }
    }

    private func refreshAutomaticTitle(for session: TennisSession, context: ModelContext) async {
        guard session.titleOrigin == .automatic, !Task.isCancelled else { return }
        session.title = ""
        session.automaticTitleState = .generating
        guard save(context, failureMessage: "Não foi possível iniciar a geração do título.") else {
            session.automaticTitleState = .failed
            return
        }
        let style = TitleStyle.current
        let facts = titleFacts(for: session)
        let visualFrames: [CGImage]
        if style == .creative, titleGenerator.supportsVisualContext {
            visualFrames = await visualContextProvider.frames(for: visualFrameRequests(for: session))
        } else {
            visualFrames = []
        }
        guard !Task.isCancelled else { return }
        let outcome = await titleGenerator.generate(
            for: facts,
            style: style,
            visualFrames: visualFrames
        )
        guard session.titleOrigin == .automatic, !Task.isCancelled else { return }
        switch outcome {
        case .generated(let title):
            session.title = title
            session.automaticTitleState = .generated
        case .unavailable(let state):
            session.title = ""
            session.automaticTitleState = state
        case .failed:
            session.title = ""
            session.automaticTitleState = .failed
        }
        session.updatedAt = .now
        save(context, failureMessage: "Não foi possível salvar o título automático.")
    }

    private func shouldResumeAutomaticTitle(for session: TennisSession) -> Bool {
        guard session.titleOrigin == .automatic else { return false }
        return switch session.automaticTitleState {
        case .legacy, .pending, .generating, .modelNotReady:
            true
        case .notApplicable, .generated, .unsupportedOS, .deviceNotEligible,
             .appleIntelligenceNotEnabled, .unsupportedLanguage, .failed:
            false
        }
    }

    private func titleFacts(for session: TennisSession) -> SessionTitleFacts {
        SessionTitleFacts(
            kind: session.kind,
            playedAt: session.playedAt,
            recordedDuration: session.recordedDuration,
            opponent: session.opponent,
            location: session.displayLocation,
            recordingCount: session.videos.count,
            rallyCount: session.clips.count
        )
    }

    private func representativeCoordinate(for session: TennisSession) -> (latitude: Double, longitude: Double)? {
        let coordinates = session.sortedVideos.compactMap { video -> (Double, Double)? in
            guard let latitude = video.latitude, let longitude = video.longitude else { return nil }
            return (latitude, longitude)
        }
        guard !coordinates.isEmpty else { return nil }
        let latitude = coordinates.reduce(0) { $0 + $1.0 } / Double(coordinates.count)
        let longitude = coordinates.reduce(0) { $0 + $1.1 } / Double(coordinates.count)
        return (latitude, longitude)
    }

    private func visualFrameRequests(for session: TennisSession) -> [SessionVisualFrameRequest] {
        session.clips
            .sorted { $0.confidence > $1.confidence }
            .prefix(3)
            .compactMap { clip in
                guard let video = session.videos.first(where: { $0.id == clip.sourceVideoID }) else {
                    return nil
                }
                return SessionVisualFrameRequest(
                    videoURL: storage.url(for: session.id, relativePath: video.relativePath),
                    time: clip.start + clip.duration / 2
                )
            }
    }

    private func isActiveEnrichment(for sessionID: UUID, requestID: UUID) -> Bool {
        !Task.isCancelled && enrichmentRequestIDs[sessionID] == requestID
    }

    private func finishEnrichment(for sessionID: UUID, requestID: UUID) {
        guard enrichmentRequestIDs[sessionID] == requestID else { return }
        enrichmentTasks[sessionID] = nil
        enrichmentRequestIDs[sessionID] = nil
    }

    private func finishTask(for sessionID: UUID, requestID: UUID) {
        guard activeRequestIDs[sessionID] == requestID else { return }
        activeTasks[sessionID] = nil
        activeRequestIDs[sessionID] = nil
    }

    @discardableResult
    private func save(_ context: ModelContext, failureMessage: String) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            notice = .error(failureMessage)
            return false
        }
    }

    private static func label(for stage: ProcessingStage) -> String {
        switch stage {
        case .preparing: "Preparando gravações"
        case .readingAudio: "Lendo gravação"
        case .findingImpacts: "Encontrando jogadas"
        case .assemblingRallies: "Separando jogadas"
        case .exporting: "Montando seu vídeo"
        }
    }

    private static func compilationLabel(for progress: Double) -> String {
        switch progress {
        case ..<0.36: "Reunindo jogadas"
        case ..<0.68: "Ajustando cortes"
        case ..<0.9: "Finalizando seu vídeo"
        default: "Preparando para compartilhar"
        }
    }

    private static func partialAnalysisMessage(
        failedVideoNames: [String],
        totalVideoCount: Int
    ) -> String? {
        guard !failedVideoNames.isEmpty else { return nil }
        let failedVideoCount = failedVideoNames.count
        let subject: String
        if failedVideoCount == 1, let name = failedVideoNames.first {
            subject = name
        } else {
            subject = "\(failedVideoCount) gravações"
        }
        let remainder = totalVideoCount - failedVideoNames.count
        let result = remainder == 1 ? "A outra foi processada" : "As outras foram processadas"
        return "\(subject) não gerou jogadas. \(result) normalmente."
    }
}
