// ActivityKit's Activity reference is not annotated as Sendable in the iOS 17
// compatibility surface. Keep that framework boundary preconcurrency while all
// access to the stored activities remains serialized on the main actor.
@preconcurrency import ActivityKit
import Foundation

@MainActor
final class ProcessingActivityController {
    private var activities: [UUID: Activity<TennisProcessingAttributes>] = [:]
    private var lastProgress: [UUID: Double] = [:]

    func start(
        sessionID: UUID,
        title: String,
        stage: String,
        totalVideos: Int
    ) async {
        if #available(iOS 26.0, *) {
            // Continued processing tasks provide their own progress surface on iOS 26.
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let existing = activities[sessionID] {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        let attributes = TennisProcessingAttributes(
            sessionID: sessionID.uuidString,
            title: title
        )
        let state = TennisProcessingAttributes.ContentState(
            progress: 0,
            stage: stage,
            currentVideo: 1,
            totalVideos: max(totalVideos, 1)
        )
        do {
            activities[sessionID] = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            lastProgress[sessionID] = 0
        } catch {
            // Live Activities are an enhancement; processing continues without one.
        }
    }

    func update(
        sessionID: UUID,
        progress: Double,
        stage: String,
        currentVideo: Int,
        totalVideos: Int
    ) async {
        guard let activity = activities[sessionID] else { return }
        let previous = lastProgress[sessionID] ?? 0
        guard progress >= 1 || progress - previous >= 0.015 else { return }
        lastProgress[sessionID] = progress
        let state = TennisProcessingAttributes.ContentState(
            progress: min(max(progress, 0), 1),
            stage: stage,
            currentVideo: currentVideo,
            totalVideos: max(totalVideos, 1)
        )
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func end(sessionID: UUID, finalStage: String, success: Bool) async {
        guard let activity = activities.removeValue(forKey: sessionID) else { return }
        let previousProgress = lastProgress.removeValue(forKey: sessionID) ?? 0
        let state = TennisProcessingAttributes.ContentState(
            progress: success ? 1 : previousProgress,
            stage: finalStage,
            currentVideo: 1,
            totalVideos: 1
        )
        await activity.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: success ? .after(.now + 12) : .default
        )
    }
}
