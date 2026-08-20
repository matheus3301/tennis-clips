import SwiftUI

struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            label(configuration)
                .glassEffect(
                    .regular.tint(configuration.isPressed ? AppPalette.hardCourt : AppPalette.baseline).interactive(),
                    in: .rect(cornerRadius: 16)
                )
        } else {
            label(configuration)
                .background(
                    configuration.isPressed ? AppPalette.hardCourt : AppPalette.baseline,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
    }

    private func label(_ configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(AppPalette.chalk)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct QuietActionButtonStyle: ButtonStyle {
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            label(configuration)
                .glassEffect(
                    .regular.tint(AppPalette.courtMist.opacity(0.5)).interactive(),
                    in: .rect(cornerRadius: 16)
                )
        } else {
            label(configuration)
                .background(
                    AppPalette.courtMist.opacity(configuration.isPressed ? 0.9 : 0.62),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
    }

    private func label(_ configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(AppPalette.baseline)
    }
}

extension View {
    func displayType(size: CGFloat, weight: Font.Weight = .black) -> some View {
        font(.system(displayTextStyle(for: size), design: .default).weight(weight).width(.condensed))
    }

    private func displayTextStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 40...: .largeTitle
        case 32...: .title
        case 28...: .title2
        default: .title3
        }
    }
}
