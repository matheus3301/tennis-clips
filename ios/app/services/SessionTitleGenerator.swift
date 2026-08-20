import CoreGraphics
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
struct SessionTitleGenerator: SessionTitleGenerating {
    var supportsVisualContext: Bool {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) { return true }
        #endif
        return false
    }

    func fallback(for facts: SessionTitleFacts, style: TitleStyle) -> String {
        let subject = facts.kind.title
        if let location = facts.location, !location.isEmpty {
            return style == .creative
                ? subject + " " + facts.periodOfDay + " no " + location
                : subject + " no " + location
        }
        return subject + " " + facts.periodOfDay
    }

    func generate(
        for facts: SessionTitleFacts,
        style: TitleStyle,
        visualFrames: [CGImage] = []
    ) async -> String? {
        guard !Task.isCancelled else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await generateWithFoundationModels(
                for: facts,
                style: style,
                visualFrames: visualFrames
            )
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateWithFoundationModels(
        for facts: SessionTitleFacts,
        style: TitleStyle,
        visualFrames: [CGImage]
    ) async -> String? {
        let model = SystemLanguageModel.default
        let locale = Locale(identifier: "pt_BR")
        guard model.availability == .available, model.supportsLocale(locale) else { return nil }

        let styleInstruction = style == .creative
            ? "Seja expressivo e variado, mas continue factual."
            : "Seja direto, factual e consistente."
        let instructions = "Você cria títulos curtos em português brasileiro para sessões de tênis. "
            + styleInstruction
            + " Use somente os fatos fornecidos ou diretamente visíveis nas imagens anexadas."
            + " Nunca infira identidade, gênero, etnia, saúde, habilidade, placar ou resultado."
            + " Só mencione roupa, iluminação, clima ou quadra quando o detalhe estiver claramente visível."
            + " Produza de 2 a 8 palavras, sem aspas, ponto final ou emoji."
        let session = LanguageModelSession(instructions: instructions)
        let location = Self.promptValue(facts.location ?? "não informado")
        let opponent = Self.promptValue(
            facts.opponent.isEmpty ? "não informado" : facts.opponent
        )
        let prompt = [
            "Tipo: " + facts.kind.title,
            "Período: " + facts.periodOfDay,
            "Duração gravada em minutos: " + String(Int(facts.recordedDuration / 60)),
            "Local: " + location,
            "Adversário: " + opponent,
            "Gravações: " + String(facts.recordingCount),
            "Jogadas encontradas: " + String(facts.rallyCount),
            visualFrames.isEmpty
                ? "Imagens: não fornecidas"
                : "Imagens: frames reais desta sessão de tênis",
        ].joined(separator: "\n")

        do {
            let options = GenerationOptions(
                sampling: style == .creative ? .random(probabilityThreshold: 0.9) : .greedy,
                temperature: style == .creative ? 0.8 : 0.2,
                maximumResponseTokens: 32
            )
            let response: LanguageModelSession.Response<GeneratedSessionTitle>
            #if compiler(>=6.4)
            if #available(iOS 27.0, *), style == .creative, !visualFrames.isEmpty {
                let multimodalPrompt = Prompt {
                    prompt
                    for frame in visualFrames {
                        Attachment(frame)
                    }
                }
                response = try await session.respond(
                    to: multimodalPrompt,
                    generating: GeneratedSessionTitle.self,
                    options: options
                )
            } else {
                response = try await session.respond(
                    to: prompt,
                    generating: GeneratedSessionTitle.self,
                    options: options
                )
            }
            #else
            response = try await session.respond(
                to: prompt,
                generating: GeneratedSessionTitle.self,
                options: options
            )
            #endif
            return Self.validated(response.content.title)
        } catch {
            return nil
        }
    }
    #endif

    nonisolated static func validated(_ value: String) -> String? {
        let title = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.,"))
        let wordCount = title.split(whereSeparator: \Character.isWhitespace).count
        guard !title.isEmpty,
              title.count <= 80,
              (2...8).contains(wordCount),
              !title.contains("\n") else {
            return nil
        }
        return title
    }

    nonisolated static func promptValue(_ value: String) -> String {
        String(
            value
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
                .prefix(120)
        )
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "Um título curto e factual para uma sessão de tênis")
private struct GeneratedSessionTitle {
    @Guide(description: "De 2 a 8 palavras em português brasileiro, sem aspas ou pontuação final")
    let title: String
}
#endif
