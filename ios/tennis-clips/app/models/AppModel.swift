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

    init(processor: any TennisProcessing = OnDeviceTennisProcessor()) {
        self.processor = processor
    }

    func process(videoAt url: URL) {
        phase = .processing(ProcessingUpdate(stage: .preparing, fraction: 0))
        Task {
            do {
                let session = try await processor.process(videoAt: url) { [weak self] update in
                    self?.phase = .processing(update)
                }
                phase = .completed(session)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func startOver() {
        phase = .idle
    }

    func reportFailure(_ error: Error) {
        phase = .failed(error.localizedDescription)
    }
}
