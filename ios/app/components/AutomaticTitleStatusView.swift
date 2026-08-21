import SwiftData
import SwiftUI

struct AutomaticTitleStatusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    let session: TennisSession

    var body: some View {
        if shouldShowStatus {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AppPalette.hardCourt)
                    }
                    Text(statusTitle)
                        .bold()
                }

                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if session.automaticTitleState.canRetry {
                    Button(
                        "Tentar gerar título",
                        systemImage: "arrow.clockwise",
                        action: retry
                    )
                    .font(.footnote.bold())
                }
            }
        }
    }

    private var shouldShowStatus: Bool {
        session.titleOrigin == .automatic
            && session.automaticTitleState != .generated
            && session.automaticTitleState != .notApplicable
    }

    private var isGenerating: Bool {
        switch session.automaticTitleState {
        case .legacy, .pending, .generating:
            true
        case .notApplicable, .generated, .unsupportedOS, .deviceNotEligible,
             .appleIntelligenceNotEnabled, .modelNotReady, .unsupportedLanguage, .failed:
            false
        }
    }

    private var statusTitle: String {
        switch session.automaticTitleState {
        case .legacy, .pending: "Título aguardando geração"
        case .generating: "Gerando título com Apple Intelligence"
        case .unsupportedOS: "Apple Intelligence indisponível neste iOS"
        case .deviceNotEligible: "Apple Intelligence indisponível neste iPhone"
        case .appleIntelligenceNotEnabled: "Apple Intelligence está desativado"
        case .modelNotReady: "O modelo ainda está sendo preparado"
        case .unsupportedLanguage: "O idioma atual não é compatível"
        case .failed: "Não foi possível gerar o título"
        case .notApplicable, .generated: ""
        }
    }

    private var statusMessage: String {
        switch session.automaticTitleState {
        case .legacy, .pending, .generating:
            "O título aparecerá automaticamente quando estiver pronto."
        case .unsupportedOS:
            "Atualize o iPhone para usar títulos gerados no aparelho."
        case .deviceNotEligible:
            "Você ainda pode definir um título manualmente em Editar."
        case .appleIntelligenceNotEnabled:
            "Ative o Apple Intelligence nos Ajustes do iPhone e tente novamente."
        case .modelNotReady:
            "Aguarde o download terminar e tente novamente."
        case .unsupportedLanguage:
            "Altere o idioma do aplicativo ou defina um título manualmente."
        case .failed:
            "Tente novamente ou defina um título manualmente em Editar."
        case .notApplicable, .generated:
            ""
        }
    }

    private func retry() {
        model.retryAutomaticTitle(for: session, context: modelContext)
    }
}
