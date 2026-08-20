import PhotosUI
import SwiftData
import SwiftUI

private struct SessionEditIssue: Identifiable {
    let id = UUID()
    let message: String
}

struct EditSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let session: TennisSession

    @State private var kind: SessionKind
    @State private var title: String
    @State private var opponent: String
    @State private var playedAt: Date
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var issue: SessionEditIssue?
    @State private var recordingPendingRemoval: SessionVideo?

    init(session: TennisSession) {
        self.session = session
        _kind = State(initialValue: session.kind)
        _title = State(initialValue: session.title)
        _opponent = State(initialValue: session.opponent)
        _playedAt = State(initialValue: session.playedAt)
    }

    var body: some View {
        let selectedItemCount = selectedItems.count

        NavigationStack {
            Form {
                Section("Tipo") {
                    Picker("Tipo", selection: $kind) {
                        ForEach(SessionKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Detalhes") {
                    TextField("Nome", text: $title)
                        .textInputAutocapitalization(.sentences)
                    DatePicker("Data", selection: $playedAt, displayedComponents: .date)
                    if kind == .match {
                        TextField("Adversário (opcional)", text: $opponent)
                            .textInputAutocapitalization(.words)
                    }
                }

                Section("Gravações") {
                    ForEach(session.sortedVideos) { video in
                        HStack(spacing: 12) {
                            Image(systemName: "video.fill")
                                .foregroundStyle(AppPalette.hardCourt)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(video.originalName)
                                    .lineLimit(1)
                                if video.duration > 0 {
                                    Text(video.duration.shortDuration)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Remover", systemImage: "trash", role: .destructive) {
                                recordingPendingRemoval = video
                            }
                            .labelStyle(.iconOnly)
                            .disabled(isImporting || model.isBusy(session) || session.videos.count == 1)
                        }
                    }

                    if session.videos.count < 8 {
                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: 8 - session.videos.count,
                            matching: .videos
                        ) {
                            Label(
                                selectedItemCount == 0
                                    ? "Adicionar gravações"
                                    : "\(selectedItemCount) para adicionar",
                                systemImage: "video.badge.plus"
                            )
                        }
                        .disabled(isImporting || model.isBusy(session))

                        if !selectedItems.isEmpty {
                            Button("Adicionar e reanalisar", action: importRecordings)
                                .disabled(isImporting)
                        }
                    } else {
                        Label("Limite de 8 gravações atingido", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }

                    Text("Ao alterar as gravações, o app procura as jogadas novamente e reinicia as escolhas desta sessão.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Editar sessão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save)
                        .disabled(isImporting)
                }
            }
            .alert("Não foi possível alterar a sessão", isPresented: issueBinding) {
                Button("Entendi", role: .cancel) {}
            } message: {
                Text(issue?.message ?? "Tente novamente.")
            }
            .confirmationDialog(
                "Remover esta gravação?",
                isPresented: removalBinding,
                titleVisibility: .visible
            ) {
                Button("Remover e reanalisar", role: .destructive, action: removeRecording)
                Button("Cancelar", role: .cancel) { recordingPendingRemoval = nil }
            } message: {
                Text("As jogadas e escolhas atuais serão recalculadas com as gravações restantes.")
            }
        }
    }

    private var issueBinding: Binding<Bool> {
        Binding(
            get: { issue != nil },
            set: { if !$0 { issue = nil } }
        )
    }

    private var removalBinding: Binding<Bool> {
        Binding(
            get: { recordingPendingRemoval != nil },
            set: { if !$0 { recordingPendingRemoval = nil } }
        )
    }

    private func save() {
        let didSave = model.updateSession(
            session,
            kind: kind,
            title: title,
            opponent: opponent,
            playedAt: playedAt,
            context: modelContext
        )
        if didSave { dismiss() }
    }

    private func importRecordings() {
        isImporting = true
        Task {
            var movies: [ImportedMovie] = []
            do {
                for item in selectedItems {
                    guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                        throw ProcessingError.cannotReadMedia
                    }
                    movies.append(movie)
                }
                guard !movies.isEmpty else { throw ProcessingError.cannotReadMedia }
                try await model.validateImports(movies)
                try model.addRecordings(movies, to: session, context: modelContext)
                selectedItems = []
                dismiss()
            } catch {
                movies.forEach { $0.removeLocalCopy() }
                issue = SessionEditIssue(message: error.localizedDescription)
                isImporting = false
            }
        }
    }

    private func removeRecording() {
        guard let recordingPendingRemoval else { return }
        do {
            try model.removeRecording(recordingPendingRemoval, from: session, context: modelContext)
            self.recordingPendingRemoval = nil
            dismiss()
        } catch {
            issue = SessionEditIssue(message: error.localizedDescription)
            self.recordingPendingRemoval = nil
        }
    }
}
