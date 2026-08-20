import Foundation
import Observation
import TennisClipsCore

@MainActor
@Observable
final class AppModel {
    enum Phase {
        case idle
        case processing(ProcessingUpdate)
        case completed(TrainingSession)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private let processor: any TennisProcessing
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var activeRequestID: UUID?

    init(processor: any TennisProcessing = OnDeviceTennisProcessor()) {
        self.processor = processor
    }

    func process(movie: ImportedMovie) {
        processingTask?.cancel()
        let requestID = UUID()
        activeRequestID = requestID
        phase = .processing(ProcessingUpdate(stage: .preparing, fraction: 0))
        processingTask = Task {
            defer {
                movie.removeLocalCopy()
                if activeRequestID == requestID {
                    processingTask = nil
                    activeRequestID = nil
                }
            }
            do {
                let session = try await processor.process(videoAt: movie.url) { [weak self] update in
                    guard self?.activeRequestID == requestID else { return }
                    self?.phase = .processing(update)
                }
                guard activeRequestID == requestID else { return }
                phase = .completed(session)
            } catch is CancellationError {
                return
            } catch {
                guard activeRequestID == requestID else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func startOver() {
        processingTask?.cancel()
        processingTask = nil
        activeRequestID = nil
        if case .completed(let session) = phase {
            try? FileManager.default.removeItem(at: session.outputURL)
        }
        phase = .idle
    }

    func reportFailure(_ error: Error) {
        phase = .failed(error.localizedDescription)
    }
}
