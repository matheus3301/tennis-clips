import BackgroundTasks
import Foundation

struct ContinuedProcessingService: Sendable {
    static let launchQueue = DispatchQueue.main

    nonisolated private static let identifierPrefix = "dev.mmonteiro.tennisclips.processing"

    nonisolated static func identifier(
        sessionID: UUID,
        operationName: String,
        attemptID: UUID
    ) -> String {
        [
            identifierPrefix,
            operationName,
            sessionID.uuidString.lowercased(),
            attemptID.uuidString.lowercased(),
        ].joined(separator: ".")
    }

    func perform(
        sessionID: UUID,
        operationName: String,
        attemptID: UUID,
        title: String,
        subtitle: String,
        operation: @MainActor @escaping (Progress?) async -> Void
    ) async {
        guard #available(iOS 26.0, *) else {
            await operation(nil)
            return
        }

        let identifier = Self.identifier(
            sessionID: sessionID,
            operationName: operationName,
            attemptID: attemptID
        )
        await withCheckedContinuation { continuation in
            let registered = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: identifier,
                using: Self.launchQueue
            ) { task in
                guard let continuedTask = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    continuation.resume()
                    return
                }
                var operationTask: Task<Void, Never>?
                continuedTask.expirationHandler = {
                    operationTask?.cancel()
                }
                operationTask = Task {
                    continuedTask.progress.totalUnitCount = 1_000
                    await operation(continuedTask.progress)
                    continuedTask.setTaskCompleted(success: !Task.isCancelled)
                    continuation.resume()
                }
            }

            guard registered else {
                Task {
                    await operation(nil)
                    continuation.resume()
                }
                return
            }

            let request = BGContinuedProcessingTaskRequest(
                identifier: identifier,
                title: title,
                subtitle: subtitle
            )
            request.strategy = .queue
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                Task {
                    await operation(nil)
                    continuation.resume()
                }
            }
        }
    }
}
