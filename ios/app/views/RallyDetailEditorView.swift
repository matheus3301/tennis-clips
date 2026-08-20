import SwiftData
import SwiftUI

struct RallyDetailEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext

    let session: TennisSession

    @State private var selectedClipID: UUID
    @State private var isClipPlaying = true
    @State private var trimSelection: ClipTrimSelection?
    @State private var decisionFeedback = 0

    init(session: TennisSession, initialClipID: UUID) {
        self.session = session
        _selectedClipID = State(initialValue: initialClipID)
    }

    var body: some View {
        ZStack {
            AppPalette.chalk.ignoresSafeArea()

            if let clip = selectedClip,
               let sourceURL = model.sourceURL(for: clip, in: session),
               let video = sourceVideo(for: clip) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        navigationHeader(for: clip)

                        RallyPlayerView(
                            url: sourceURL,
                            start: clip.start,
                            end: clip.end,
                            isPlaying: $isClipPlaying
                        )
                        .frame(height: 360)
                        .clipShape(.rect(cornerRadius: 24))
                        .overlay(alignment: .bottomTrailing) {
                            Button(
                                isClipPlaying ? "Pausar jogada" : "Reproduzir jogada",
                                systemImage: isClipPlaying ? "pause.fill" : "play.fill",
                                action: togglePlayback
                            )
                            .labelStyle(.iconOnly)
                            .font(.headline.bold())
                            .foregroundStyle(AppPalette.chalk)
                            .frame(width: 48, height: 48)
                            .background(.ultraThinMaterial, in: Circle())
                            .environment(\.colorScheme, .dark)
                            .padding(14)
                        }

                        RallySourceTimeline(
                            video: video,
                            clips: sourceClips(for: video),
                            selectedClipID: clip.id
                        )

                        RallyDecisionBar(decision: clip.decision, onDecisionChange: updateDecision)

                        Button("Ajustar início e fim", systemImage: "slider.horizontal.3") {
                            presentTrimEditor(for: clip, sourceURL: sourceURL, video: video)
                        }
                        .buttonStyle(QuietActionButtonStyle())

                        Menu("Mais ajustes", systemImage: "ellipsis.circle") {
                            Button("Dividir em duas jogadas", systemImage: "rectangle.split.2x1", action: split)
                                .disabled(clip.duration < 2)
                            Button("Unir com a próxima", systemImage: "rectangle.on.rectangle", action: merge)
                                .disabled(!canMergeWithNext(clip))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(AppPalette.baseline)

                        if let clipURL = model.clipOutputURL(for: clip, in: session) {
                            ShareLink(item: clipURL) {
                                Label("Compartilhar jogada", systemImage: "square.and.arrow.up")
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(AppPalette.baseline)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
                .scrollContentBackground(.visible)
            } else {
                ContentUnavailableView(
                    "Jogada não encontrada",
                    systemImage: "rectangle.slash",
                    description: Text("Ela pode ter sido alterada durante a edição.")
                )
            }
        }
        .navigationTitle("Editar jogada")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: decisionFeedback)
        .sheet(item: $trimSelection) { selection in
            ClipTrimView(selection: selection)
        }
    }

    private var clips: [RallyClip] { session.sortedClips }
    private var selectedIndex: Int? { clips.firstIndex { $0.id == selectedClipID } }
    private var selectedClip: RallyClip? {
        guard let selectedIndex, clips.indices.contains(selectedIndex) else { return nil }
        return clips[selectedIndex]
    }

    private func navigationHeader(for clip: RallyClip) -> some View {
        HStack {
            Button("Jogada anterior", systemImage: "chevron.left", action: selectPrevious)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .disabled(selectedIndex == clips.startIndex)

            VStack(spacing: 3) {
                Text("JOGADA \(clip.order + 1) DE \(clips.count)")
                    .font(.caption.bold())
                    .tracking(1.3)
                    .foregroundStyle(AppPalette.hardCourt)
                Text(clip.decision == .kept ? "No vídeo" : "Fora do vídeo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button("Próxima jogada", systemImage: "chevron.right", action: selectNext)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .disabled(selectedIndex == clips.index(before: clips.endIndex))
        }
    }

    private func sourceVideo(for clip: RallyClip) -> SessionVideo? {
        session.videos.first { $0.id == clip.sourceVideoID }
    }

    private func sourceClips(for video: SessionVideo) -> [RallyClip] {
        clips.filter { $0.sourceVideoID == video.id }
    }

    private func updateDecision(_ decision: RallyDecision) {
        guard let clip = selectedClip, clip.decision != decision else { return }
        model.decide(decision, for: clip, in: session, context: modelContext)
        decisionFeedback += 1
    }

    private func selectPrevious() {
        guard let selectedIndex, clips.indices.contains(selectedIndex - 1) else { return }
        select(clips[selectedIndex - 1])
    }

    private func selectNext() {
        guard let selectedIndex, clips.indices.contains(selectedIndex + 1) else { return }
        select(clips[selectedIndex + 1])
    }

    private func select(_ clip: RallyClip) {
        selectedClipID = clip.id
        isClipPlaying = true
    }

    private func togglePlayback() {
        isClipPlaying.toggle()
    }

    private func presentTrimEditor(for clip: RallyClip, sourceURL: URL, video: SessionVideo) {
        trimSelection = ClipTrimSelection(
            session: session,
            clip: clip,
            sourceURL: sourceURL,
            videoDuration: max(video.duration, clip.end)
        )
    }

    private func split() {
        guard let clip = selectedClip else { return }
        _ = model.splitClip(clip, in: session, context: modelContext)
    }

    private func merge() {
        guard let clip = selectedClip else { return }
        _ = model.mergeWithNextClip(clip, in: session, context: modelContext)
    }

    private func canMergeWithNext(_ clip: RallyClip) -> Bool {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }),
              clips.indices.contains(index + 1)
        else { return false }
        return clips[index + 1].sourceVideoID == clip.sourceVideoID
    }
}
