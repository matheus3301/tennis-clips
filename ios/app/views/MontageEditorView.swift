import SwiftData
import SwiftUI

struct MontageEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext

    let session: TennisSession

    @State private var history: [(clipID: UUID, decision: RallyDecision)] = []
    @State private var decisionFeedback = 0

    var body: some View {
        ZStack {
            AppPalette.chalk.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    MontageSummaryHeader(
                        includedCount: includedClips.count,
                        rejectedCount: rejectedClips.count,
                        duration: session.compiledDuration
                    )

                    RallyGallerySection(
                        title: "NO VÍDEO",
                        emptyTitle: "Nenhuma jogada no vídeo",
                        emptySymbol: "rectangle.stack.badge.minus",
                        clips: includedClips,
                        session: session,
                        singleColumn: dynamicTypeSize.isAccessibilitySize,
                        onDecisionChange: updateDecision
                    )

                    RallyGallerySection(
                        title: "FORA DO VÍDEO",
                        emptyTitle: "Nenhuma jogada fora do vídeo",
                        emptySymbol: "checkmark.circle",
                        clips: rejectedClips,
                        session: session,
                        singleColumn: dynamicTypeSize.isAccessibilitySize,
                        onDecisionChange: updateDecision
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .padding(.bottom, session.status == .ready ? 96 : 28)
            }
            .scrollContentBackground(.visible)
        }
        .navigationTitle("Jogadas do vídeo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Desfazer", systemImage: "arrow.uturn.backward", action: undo)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if session.status == .ready {
                compilationBar
            }
        }
        .sensoryFeedback(.selection, trigger: decisionFeedback)
    }

    private var includedClips: [RallyClip] {
        session.sortedClips.filter { $0.decision == .kept }
    }

    private var rejectedClips: [RallyClip] {
        session.sortedClips.filter { $0.decision == .rejected }
    }

    private var compilationBar: some View {
        VStack(spacing: 7) {
            Text(compilationSummary)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)

            Button(action: compile) {
                Label(compilationTitle, systemImage: session.outputPath == nil ? "play.rectangle.fill" : "arrow.clockwise")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(includedClips.isEmpty)
            .opacity(includedClips.isEmpty ? 0.48 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var compilationTitle: String {
        session.outputPath == nil ? "Montar vídeo" : "Atualizar vídeo"
    }

    private var compilationSummary: String {
        "\(includedClips.count) jogadas · \(session.compiledDuration.shortDuration)"
    }

    private func updateDecision(_ clip: RallyClip, _ decision: RallyDecision) {
        guard clip.decision != decision else { return }
        history.append((clip.id, clip.decision))
        persist(decision, for: clip)
    }

    private func undo() {
        guard let change = history.popLast(),
              let clip = session.clips.first(where: { $0.id == change.clipID })
        else { return }
        persist(change.decision, for: clip)
    }

    private func persist(_ decision: RallyDecision, for clip: RallyClip) {
        if reduceMotion {
            model.decide(decision, for: clip, in: session, context: modelContext)
        } else {
            withAnimation(.snappy(duration: 0.3)) {
                model.decide(decision, for: clip, in: session, context: modelContext)
            }
        }
        decisionFeedback += 1
    }

    private func compile() {
        if model.compile(session, context: modelContext) {
            dismiss()
        }
    }
}
