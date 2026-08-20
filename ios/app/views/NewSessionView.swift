import PhotosUI
import SwiftData
import SwiftUI

struct NewSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onCreated: (UUID) -> Void

    @State private var kind: SessionKind = .match
    @State private var title = ""
    @State private var opponent = ""
    @State private var playedAt = Date()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppPalette.chalk.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        intro
                        kindPicker
                        details
                        recordings
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                createBar
            }
            .navigationTitle("Nova sessão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                        .disabled(isImporting)
                }
            }
            .alert("Não foi possível criar a sessão", isPresented: errorBinding) {
                Button("Tentar novamente", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Revise as gravações selecionadas.")
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Um lugar para este dia na quadra.")
                .displayType(size: 32)
                .foregroundStyle(AppPalette.ink)
            Text("Você pode juntar várias gravações. O app encontra as jogadas e deixa a escolha final com você.")
                .font(.body)
                .foregroundStyle(AppPalette.ink.opacity(0.62))
                .lineSpacing(3)
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("O que você gravou?")
                .font(.headline)
            Picker("Tipo", selection: $kind) {
                ForEach(SessionKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Detalhes")
                .font(.headline)

            DatePicker("Data", selection: $playedAt, displayedComponents: .date)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Nome")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.ink.opacity(0.55))
                TextField(defaultTitle, text: $title)
                    .textInputAutocapitalization(.sentences)
            }

            if kind == .match {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Adversário · opcional")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.ink.opacity(0.55))
                    TextField("Com quem você jogou?", text: $opponent)
                        .textInputAutocapitalization(.words)
                }
            }
        }
        .padding(18)
        .background(AppPalette.courtMist.opacity(0.48), in: RoundedRectangle(cornerRadius: 20))
    }

    private var recordings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Gravações")
                        .font(.headline)
                    Text("Escolha até 8 vídeos do mesmo dia.")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.ink.opacity(0.56))
                }
                Spacer()
                if !selectedItems.isEmpty {
                    Text(String(selectedItems.count))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(AppPalette.baseline)
                        .frame(width: 34, height: 34)
                        .background(AppPalette.ball, in: Circle())
                }
            }

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 8,
                matching: .videos
            ) {
                Label(
                    selectedItems.isEmpty ? "Escolher vídeos" : "Alterar vídeos",
                    systemImage: "video.badge.plus"
                )
            }
            .buttonStyle(QuietActionButtonStyle())
            .disabled(isImporting)
        }
        .padding(18)
        .background(AppPalette.courtMist.opacity(0.48), in: RoundedRectangle(cornerRadius: 20))
    }

    private var createBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(AppPalette.baseline.opacity(0.08))

            Button {
                importAndCreate()
            } label: {
                HStack(spacing: 10) {
                    if isImporting {
                        ProgressView().tint(AppPalette.chalk)
                    } else {
                        Image(systemName: "sparkles.rectangle.stack")
                    }
                    Text(isImporting ? "Importando gravações" : "Encontrar jogadas")
                }
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(selectedItems.isEmpty || isImporting)
            .opacity(selectedItems.isEmpty ? 0.48 : 1)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var defaultTitle: String {
        kind == .match ? "Jogo de quinta" : "Treino de saque"
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func importAndCreate() {
        isImporting = true
        errorMessage = nil
        Task {
            var movies: [ImportedMovie] = []
            do {
                for item in selectedItems {
                    guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                        continue
                    }
                    movies.append(movie)
                }
                guard !movies.isEmpty else {
                    throw ProcessingError.cannotReadMedia
                }
                let session = try model.createSession(
                    kind: kind,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    opponent: opponent.trimmingCharacters(in: .whitespacesAndNewlines),
                    playedAt: playedAt,
                    movies: movies,
                    context: modelContext
                )
                onCreated(session.id)
                dismiss()
            } catch {
                movies.forEach { $0.removeLocalCopy() }
                errorMessage = error.localizedDescription
                isImporting = false
            }
        }
    }
}

#Preview("Nova sessão") {
    NewSessionView { _ in }
        .environment(AppModel())
        .modelContainer(
            for: [TennisSession.self, SessionVideo.self, RallyClip.self],
            inMemory: true
        )
}
