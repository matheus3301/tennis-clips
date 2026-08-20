import SwiftData
import SwiftUI
import UIKit

struct RallyReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let session: TennisSession

    @State private var currentIndex: Int
    @State private var dragOffset: CGSize = .zero
    @State private var history: [UUID] = []

    init(session: TennisSession) {
        self.session = session
        let clips = session.sortedClips
        _currentIndex = State(initialValue: clips.firstIndex { $0.decision == .pending } ?? 0)
    }

    var body: some View {
        ZStack {
            AppPalette.chalk.ignoresSafeArea()
            if let clip = currentClip, let sourceURL = model.sourceURL(for: clip, in: session) {
                review(clip: clip, sourceURL: sourceURL)
            } else {
                completion
            }
        }
        .navigationTitle("Revisar jogadas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Concluir") { dismiss() }
            }
        }
    }

    private func review(clip: RallyClip, sourceURL: URL) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("JOGADA " + String(currentIndex + 1))
                    .font(.caption.weight(.black))
                    .tracking(1.5)
                    .foregroundStyle(AppPalette.hardCourt)
                Spacer()
                Text(String(session.reviewedClipCount) + " de " + String(clips.count))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(AppPalette.ink.opacity(0.52))
            }

            RallyRail(decisions: clips.map(\.decision), currentIndex: currentIndex)

            ZStack {
                RallyPlayerView(url: sourceURL, start: clip.start, end: clip.end)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                swipeFeedback
            }
            .frame(maxHeight: .infinity)
            .offset(x: dragOffset.width, y: dragOffset.height * 0.12)
            .rotationEffect(.degrees(Double(dragOffset.width / 24)))
            .highPriorityGesture(dragGesture)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: dragOffset)

            actionRow(clip: clip)

            Button("Desfazer última escolha", systemImage: "arrow.uturn.backward") {
                undo()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppPalette.ink.opacity(history.isEmpty ? 0.28 : 0.58))
            .disabled(history.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var completion: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .fill(AppPalette.ball)
                    .frame(width: 104, height: 104)
                Image(systemName: "checkmark")
                    .font(.system(size: 42, weight: .black))
                    .foregroundStyle(AppPalette.baseline)
            }
            Text("Todas as jogadas foram revisadas.")
                .displayType(size: 34)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppPalette.ink)
            Text(String(session.keptClips.count) + " entram no seu vídeo.")
                .foregroundStyle(AppPalette.ink.opacity(0.58))
            Button("Ver resumo") { dismiss() }
                .buttonStyle(PrimaryActionButtonStyle())
                .padding(.top, 8)
            if !history.isEmpty {
                Button("Desfazer última escolha", action: undo)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppPalette.baseline)
            }
            Spacer()
        }
        .padding(26)
    }

    private var swipeFeedback: some View {
        HStack {
            if dragOffset.width > 22 {
                decisionStamp("INCLUIR", color: AppPalette.ball, rotation: -8)
            }
            Spacer()
            if dragOffset.width < -22 {
                decisionStamp("DESCARTAR", color: AppPalette.clayMark, rotation: 8)
            }
        }
        .padding(24)
        .allowsHitTesting(false)
    }

    private func decisionStamp(_ text: String, color: Color, rotation: Double) -> some View {
        Text(text)
            .font(.headline.weight(.black))
            .tracking(1.3)
            .foregroundStyle(color)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(rotation))
    }

    private func actionRow(clip: RallyClip) -> some View {
        HStack(spacing: 26) {
            ReviewActionButton(
                label: "Descartar",
                symbol: "xmark",
                color: AppPalette.clayMark
            ) { commit(.rejected) }

            Button {
                Task {
                    await model.saveClip(clip, from: session, context: modelContext)
                    if clip.decision == .kept { advance() }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(AppPalette.baseline)
                        .frame(width: 66, height: 66)
                    if model.savingClipID == clip.id {
                        ProgressView().tint(AppPalette.chalk)
                    } else {
                        Image(systemName: clip.savedToPhotos ? "checkmark" : "square.and.arrow.down")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppPalette.chalk)
                    }
                }
            }
            .disabled(model.savingClipID != nil)
            .accessibilityLabel(clip.savedToPhotos ? "Jogada salva" : "Salvar jogada nas Fotos")

            ReviewActionButton(
                label: "Incluir",
                symbol: "checkmark",
                color: AppPalette.hardCourt
            ) { commit(.kept) }
        }
    }

    private var clips: [RallyClip] { session.sortedClips }

    private var currentClip: RallyClip? {
        clips.indices.contains(currentIndex) ? clips[currentIndex] : nil
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                if value.translation.width > 95 {
                    commit(.kept)
                } else if value.translation.width < -95 {
                    commit(.rejected)
                } else {
                    dragOffset = .zero
                }
            }
    }

    private func commit(_ decision: RallyDecision) {
        guard let clip = currentClip else { return }
        history.append(clip.id)
        model.decide(decision, for: clip, in: session, context: modelContext)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(decision == .kept ? .success : .warning)
        dragOffset = CGSize(width: decision == .kept ? 520 : -520, height: 0)
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            advance()
        }
    }

    private func advance() {
        dragOffset = .zero
        let updated = clips
        if let next = updated.indices.first(where: { $0 > currentIndex && updated[$0].decision == .pending }) {
            currentIndex = next
        } else if let first = updated.firstIndex(where: { $0.decision == .pending }) {
            currentIndex = first
        } else {
            currentIndex = updated.count
        }
    }

    private func undo() {
        guard let clipID = history.popLast(), let index = clips.firstIndex(where: { $0.id == clipID }) else {
            return
        }
        model.resetDecision(for: clips[index], in: session, context: modelContext)
        currentIndex = index
        dragOffset = .zero
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

private struct ReviewActionButton: View {
    let label: String
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.headline.weight(.black))
                    .frame(width: 52, height: 52)
                    .background(color.opacity(0.13), in: Circle())
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.ink.opacity(0.62))
            }
        }
    }
}
