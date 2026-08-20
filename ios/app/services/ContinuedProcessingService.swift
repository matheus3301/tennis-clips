import BackgroundTasks
import Foundation

struct ContinuedProcessingService: Sendable {
    private let identifierPrefix = "dev.mmonteiro.tennisclips.processing"

    func perform(
        sessionID: UUID,
        operationName: String,
        title: String,
        subtitle: String,
        operation: @MainActor @escaping (Progress?) async -> Void
    ) async {
        guard #available(iOS 26.0, *) else {
            await operation(nil)
            return
        }

        let suffix = operationName + "." + sessionID.uuidString.lowercased()
        let identifier = identifierPrefix + "." + suffix
        await withCheckedContinuation { continuation in
            let registered = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: identifier,
                using: nil
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
            request.strategy = .fail
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
