import SwiftUI

struct ProcessingMessageRotator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentIndex = 0

    let messages: [String]

    var body: some View {
        Text(currentMessage)
            .id(currentIndex)
            .font(.title2.bold())
            .fontWidth(.condensed)
            .multilineTextAlignment(.center)
            .foregroundStyle(AppPalette.ink)
            .frame(maxWidth: .infinity, minHeight: 76)
            .transition(messageTransition)
            .accessibilityLabel(currentMessage)
            .task(id: messageSetID) {
                await rotateMessages()
            }
    }

    private var currentMessage: String {
        guard messages.indices.contains(currentIndex) else { return messages.first ?? "" }
        return messages[currentIndex]
    }

    private var messageSetID: String {
        messages.joined(separator: "|")
    }

    private var messageTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    @MainActor
    private func rotateMessages() async {
        currentIndex = 0
        guard messages.count > 1 else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }

            withAnimation(reduceMotion ? .easeInOut(duration: 0.22) : .snappy(duration: 0.45)) {
                currentIndex = (currentIndex + 1) % messages.count
            }
        }
    }
}
