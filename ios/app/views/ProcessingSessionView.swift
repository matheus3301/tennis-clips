import SwiftUI

struct ProcessingSessionView: View {
    let session: TennisSession

    var body: some View {
        VStack(spacing: 0) {
            ProcessingMessageRotator(messages: messages)
                .padding(.top, 32)
                .padding(.horizontal, 24)
                .zIndex(1)
            SessionMetadataSummary(session: session)
                .padding(.horizontal, 24)
                .padding(.top, 16)
            ProcessingAnimation()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
            VStack(alignment: .trailing, spacing: 8) {
                Text(session.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                ProgressView(value: session.progress).tint(AppPalette.ball)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            if #unavailable(iOS 26.0) {
                Text("Mantenha o app aberto até o processamento terminar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 10)
            }
        }
    }

    private var messages: [String] {
        session.status == .exporting
            ? ["Reunindo suas jogadas favoritas.", "Ajustando cada corte.", "Colocando tudo na ordem.", "Finalizando seu vídeo.", "Preparando para salvar e compartilhar."]
            : ["Procurando as melhores jogadas.", "Detectando cada batida.", "Separando os melhores cortes.", "Organizando tudo para sua revisão.", "Deixando cada jogada pronta para você."]
    }
}
