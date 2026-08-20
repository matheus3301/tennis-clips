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

    @ObservationIgnored private var activeTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var activeRequestIDs: [UUID: UUID] = [:]

    var notice: AppNotice?
    var savingClipID: UUID?

    init(
        analyzer: any TennisAnalyzing = OnDeviceTennisProcessor(),
        editor: RallyVideoEditor = RallyVideoEditor(),
        storage: SessionStorage = SessionStorage(),
        photoExporter: PhotoLibraryExporter = PhotoLibraryExporter(),
        activityController: ProcessingActivityController = ProcessingActivityController(),
        continuedProcessing: ContinuedProcessingService = ContinuedProcessingService(),
        mediaPreflight: MediaPreflightService = MediaPreflightService()
    ) {
        self.analyzer = analyzer
        self.editor = editor
        self.storage = storage
        self.photoExporter = photoExporter
        self.activityController = activityController
        self.continuedProcessing = continuedProcessing
        self.mediaPreflight = mediaPreflight
    }

    func validateImports(_ movies: [ImportedMovie]) async throws {
        try await mediaPreflight.validate(movies)
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
            playedAt: playedAt
        )
        context.insert(session)
        do {
            try storage.prepareSession(session.id)
            try storage.validateCapacity(for: movies)
            for (index, movie) in movies.enumerated() {
                let relativePath = try storage.persist(movie, sessionID: session.id, order: index)
                session.videos.append(SessionVideo(
                    order: index,
                    originalName: movie.originalName,
                    relativePath: relativePath
                ))
            }
            try context.save()
            startAnalysis(session, context: context)
            return session
        } catch {
            storage.removeSession(session.id)
            context.delete(session)
            throw error
        }
    }

    func addRecordings(
        _ movies: [ImportedMovie],
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
                let video = SessionVideo(
                    order: firstOrder + offset,
                    originalName: movie.originalName,
                    relativePath: relativePath
                )
                newVideos.append(video)
                session.videos.append(video)
            }
            session.outputPath = nil
            try context.save()
            storage.removeCompilation(sessionID: session.id)
            notice = .success(AppCopy.importedRecordings(movies.count) + ". Reanalisando a sessão.")
            startAnalysis(session, context: context)
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

    func startAnalysis(_ session: TennisSession, context: ModelContext) {
        cancelTask(for: session.id)
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
    }

    func resumeIfNeeded(_ sessions: [TennisSession], context: ModelContext) {
        for session in sessions where activeTasks[session.id] == nil {
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
        context: ModelContext
    ) -> Bool {
        guard start >= 0, end - start >= 0.5 else {
            notice = .warning("A jogada precisa ter pelo menos meio segundo.")
            return false
        }
        clip.start = start
        clip.end = end
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
        let secondImpactCount = max(1, clip.impactCount / 2)
        clip.end = midpoint
        clip.impactCount = max(1, clip.impactCount - secondImpactCount)
        for existing in session.clips where existing.order > clip.order {
            existing.order += 1
        }
        let secondClip = RallyClip(
            sourceVideoID: clip.sourceVideoID,
            order: clip.order + 1,
            start: midpoint,
            end: originalEnd,
            impactCount: secondImpactCount,
            confidence: clip.confidence
        )
        context.insert(secondClip)
        session.clips.append(secondClip)
        session.status = .reviewing
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
        clip.end = max(clip.end, next.end)
        clip.impactCount += next.impactCount
        clip.confidence = (clip.confidence + next.confidence) / 2
        clip.decision = .pending
        session.clips.removeAll { $0.id == next.id }
        context.delete(next)
        for (order, existing) in session.sortedClips.enumerated() {
            existing.order = order
        }
        session.status = .reviewing
        return save(context, failureMessage: "Não foi possível unir as jogadas.")
    }

    func compile(_ session: TennisSession, context: ModelContext) {
        guard !session.keptClips.isEmpty else {
            notice = .warning("Inclua pelo menos uma jogada antes de montar o vídeo.")
            return
        }
        cancelTask(for: session.id)
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
        session.opponent = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        session.playedAt = playedAt
        session.updatedAt = .now
        return save(context, failureMessage: "Não foi possível atualizar a sessão.")
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
