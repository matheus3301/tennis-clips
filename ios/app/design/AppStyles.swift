import SwiftUI

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(AppPalette.chalk)
            .background(
                configuration.isPressed ? AppPalette.hardCourt : AppPalette.baseline,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct QuietActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(AppPalette.baseline)
            .background(
                AppPalette.courtMist.opacity(configuration.isPressed ? 0.9 : 0.62),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
    }
}

extension View {
    func displayType(size: CGFloat, weight: Font.Weight = .black) -> some View {
        font(.system(size: size, weight: weight, design: .default))
            .fontWidth(.condensed)
    }
}
