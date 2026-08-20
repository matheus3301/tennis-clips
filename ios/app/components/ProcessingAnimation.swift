import Lottie
import SwiftUI

struct ProcessingAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LottieView(animation: .named("rally-processing"))
            .playing(loopMode: reduceMotion ? .playOnce : .loop)
            .scaleEffect(1.38)
            .accessibilityHidden(true)
    }
}
