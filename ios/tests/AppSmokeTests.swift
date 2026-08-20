import XCTest
import TennisClipsCore
@testable import TennisClips

final class AppSmokeTests: XCTestCase {
    @MainActor
    func testAppStartsIdle() {
        let model = AppModel()
        if case .idle = model.phase {
            return
        }
        XCTFail("The app should start idle")
    }

    @MainActor
    func testSuccessfulProcessingCleansImportAndOutputWhenStartingOver() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("tennis-clips-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("input.mov")
        let output = folder.appendingPathComponent("output.mp4")
        try Data().write(to: input)
        try Data().write(to: output)
        let session = TrainingSession(outputURL: output, impacts: [], clips: [])
        let model = AppModel(processor: SuccessfulProcessor(session: session))

        model.process(movie: ImportedMovie(url: input))

        let completed = await waitUntil {
            if case .completed = model.phase { return true }
            return false
        }
        XCTAssertTrue(completed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: input.path))

        model.startOver()

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        if case .idle = model.phase { return }
        XCTFail("The app should return to idle")
    }

    @MainActor
    func testFailedProcessingCleansImportedMovie() async throws {
        let input = FileManager.default.temporaryDirectory
            .appendingPathComponent("tennis-clips-input-\(UUID().uuidString).mov")
        try Data().write(to: input)
        defer { try? FileManager.default.removeItem(at: input) }
        let model = AppModel(processor: FailingProcessor())

        model.process(movie: ImportedMovie(url: input))

        let failed = await waitUntil {
            if case .failed = model.phase { return true }
            return false
        }
        XCTAssertTrue(failed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: input.path))
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private struct SuccessfulProcessor: TennisProcessing {
    let session: TrainingSession

    func process(
        videoAt url: URL,
        progress: @escaping @MainActor @Sendable (ProcessingUpdate) -> Void
    ) async throws -> TrainingSession {
        await progress(ProcessingUpdate(stage: .exporting, fraction: 1))
        return session
    }
}

private struct FailingProcessor: TennisProcessing {
    func process(
        videoAt url: URL,
        progress: @escaping @MainActor @Sendable (ProcessingUpdate) -> Void
    ) async throws -> TrainingSession {
        throw ProcessingError.noAudio
    }
}
