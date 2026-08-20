import SwiftUI

struct RallyDecisionBar: View {
    let decision: RallyDecision
    let onDecisionChange: (RallyDecision) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: reject) {
                Label("Fora do vídeo", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.clayMark)
            .background(
                decision == .rejected ? AppPalette.clayMark.opacity(0.14) : AppPalette.courtMist.opacity(0.42),
                in: .rect(cornerRadius: 15)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(decision == .rejected ? AppPalette.clayMark : .clear, lineWidth: 2)
            }
            .accessibilityAddTraits(decision == .rejected ? .isSelected : [])

            Button(action: include) {
                Label("No vídeo", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.hardCourt)
            .background(
                decision == .kept ? AppPalette.hardCourt.opacity(0.14) : AppPalette.courtMist.opacity(0.42),
                in: .rect(cornerRadius: 15)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(decision == .kept ? AppPalette.hardCourt : .clear, lineWidth: 2)
            }
            .accessibilityAddTraits(decision == .kept ? .isSelected : [])
        }
        .font(.subheadline.bold())
    }

    private func reject() {
        onDecisionChange(.rejected)
    }

    private func include() {
        onDecisionChange(.kept)
    }
}
