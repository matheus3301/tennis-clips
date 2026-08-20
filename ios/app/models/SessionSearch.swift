import Foundation

extension TennisSession {
    @MainActor
    func matchesSearch(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }
        return searchableText.localizedStandardContains(trimmedQuery)
    }

    @MainActor
    private var searchableText: String {
        let date = playedAt.formatted(date: .long, time: .shortened)
        let weekday = playedAt.formatted(.dateTime.weekday(.wide))
        let durationMinutes = String(Int(recordedDuration / 60)) + " minutos"
        return [
            displayTitle,
            opponent,
            kind.title,
            locationName ?? "",
            locality ?? "",
            date,
            weekday,
            recordedDuration.shortDuration,
            durationMinutes,
        ].joined(separator: " ")
    }
}
