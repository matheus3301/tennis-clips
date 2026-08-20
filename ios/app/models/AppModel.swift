import Foundation
import Observation
import SwiftData
import TennisClipsCore

@MainActor
@Observable
final class AppModel {
    private let analyzer: any TennisAnalyzing
    private let editor: RallyVideoEditor
    private let storage: SessionStorage
    private let photoExporter: PhotoLibraryExporter
    private let activityController: ProcessingActivityController
    private let continuedProcessing: ContinuedProcessingService

    @ObservationIgnored private var activeTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var activeRequestIDs: [UUID: UUID] = [:]

    var toastMessage: String?
    var savingClipID: UUID?

    init(
        analyzer: any TennisAnalyzing = OnDeviceTennisProcessor(),
        editor: RallyVideoEditor = RallyVideoEditor(),
        storage: SessionStorage = SessionStorage(),
        photoExporter: PhotoLibraryExporter = PhotoLibraryExporter(),
        activityController: ProcessingActivityController = ProcessingActivityController(),
        continuedProcessing: ContinuedProcessingService = ContinuedProcessingService()
    ) {
        self.analyzer = analyzer
        self.editor = editor
        self.storage = storage
        self.photoExporter = photoExporter
        self.activityController = activityController
        self.continuedProcessing = continuedProcessing
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
        try? context.save()
    }

    func resetDecision(
        for clip: RallyClip,
        in session: TennisSession,
        context: ModelContext
    ) {
        clip.decision = .pending
        session.status = .reviewing
        try? context.save()
    }

    func compile(_ session: TennisSession, context: ModelContext) {
        guard !session.keptClips.isEmpty else {
            toastMessage = "Inclua pelo menos uma jogada antes de montar o vídeo."
            return
        }
        cancelTask(for: session.id)
        let requestID = UUID()
        activeRequestIDs[session.id] = requestID
        session.status = .exporting
        session.progress = 0
        session.progressLabel = "Montando seu vídeo"
        session.errorMessage = nil

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
                    systemProgress: progress
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
            if clip.decision == .pending {
                decide(.kept, for: clip, in: session, context: context)
            } else {
                try? context.save()
            }
            toastMessage = "Jogada salva nas Fotos."
        } catch {
            toastMessage = error.localizedDescription
        }
    }

    func saveCompilation(_ session: TennisSession) async {
        guard let outputURL = outputURL(for: session) else { return }
        do {
            try await photoExporter.saveVideo(at: outputURL)
            toastMessage = "Vídeo salvo nas Fotos."
        } catch {
            toastMessage = error.localizedDescription
        }
    }

    func delete(_ session: TennisSession, context: ModelContext) {
        cancelTask(for: session.id)
        storage.removeSession(session.id)
        context.delete(session)
        try? context.save()
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
            for (videoIndex, video) in session.sortedVideos.enumerated() {
                try Task.checkCancellation()
                guard activeRequestIDs[session.id] == requestID else { return }
                let url = storage.url(for: session.id, relativePath: video.relativePath)
                let analysis = try await analyzer.analyze(videoAt: url) { [weak self] update in
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
            session.progressLabel = String(session.clips.count) + " jogadas prontas"
            session.status = .reviewing
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
            try? context.save()
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
        systemProgress: Progress?
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
            try await editor.export(segments: segments, to: destination) { [weak self] fraction in
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
            try? context.save()
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
}
