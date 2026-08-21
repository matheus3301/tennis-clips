import PhotosUI
import SwiftData
import SwiftUI

private struct ImportIssue: Identifiable {
    let id = UUID()
    let message: String
}

struct NewSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext

    let onCreated: (UUID) -> Void

    @State private var kind: SessionKind = .match
    @State private var opponent = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var importIssue: ImportIssue?

    var body: some View {
        NavigationStack {
            ZStack {
                AppPalette.chalk.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        intro
                        kindPicker
                        if kind == .match {
                            details
                        }
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
            .alert(item: $importIssue) { issue in
                Alert(
                    title: Text("Não foi possível criar a sessão"),
                    message: Text(issue.message),
                    dismissButton: .default(Text("Entendi"))
                )
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transforme suas gravações em jogadas.")
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Adversário · opcional")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.ink.opacity(0.55))
                TextField("Com quem você jogou?", text: $opponent)
                    .textInputAutocapitalization(.words)
            }
        }
        .padding(18)
        .background(AppPalette.courtMist.opacity(0.48), in: RoundedRectangle(cornerRadius: 20))
    }

    private var recordings: some View {
        let hasSelection = !selectedItems.isEmpty

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Gravações")
                        .font(.headline)
                    Text("Escolha até 8 vídeos do mesmo dia.")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.ink.opacity(0.56))
                }
                Spacer()
                if hasSelection {
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
                    hasSelection ? "Alterar vídeos" : "Escolher vídeos",
                    systemImage: "video.badge.plus"
                )
            }
            .buttonStyle(QuietActionButtonStyle())
            .disabled(isImporting)

            DisclosureGroup("Como gravar melhor") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Apoie o iPhone e mantenha a quadra inteira no quadro.", systemImage: "iphone.gen3")
                    Label("Preserve o áudio original para detectar as batidas.", systemImage: "waveform")
                    Label("Use vídeos de até 30 minutos; divida gravações mais longas.", systemImage: "clock")
                }
                .font(.footnote)
                .foregroundStyle(AppPalette.ink.opacity(0.7))
                .padding(.top, 8)
            }
            .font(.subheadline.weight(.semibold))
            .tint(AppPalette.baseline)
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
                createButtonLabel
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .accessibilityLabel(isImporting ? "Importando gravações" : "Encontrar jogadas")
            .disabled(selectedItems.isEmpty || isImporting)
            .opacity(selectedItems.isEmpty ? 0.48 : 1)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var createButtonLabel: some View {
        if isImporting {
            HStack(spacing: 10) {
                ProgressView().tint(AppPalette.chalk)
                Text(dynamicTypeSize.isAccessibilitySize ? "Importando" : "Importando gravações")
            }
        } else if dynamicTypeSize.isAccessibilitySize {
            Text("Analisar")
        } else {
            Label("Encontrar jogadas", systemImage: "sparkles.rectangle.stack")
        }
    }

    private func importAndCreate() {
        isImporting = true
        importIssue = nil
        Task {
            var movies: [ImportedMovie] = []
            do {
                var failedImportCount = 0
                for item in selectedItems {
                    guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                        failedImportCount += 1
                        continue
                    }
                    movies.append(movie.attachingAssetIdentifier(item.itemIdentifier))
                }
                guard !movies.isEmpty else {
                    throw ProcessingError.cannotReadMedia
                }
                let metadata = try await model.validateImports(movies)
                let session = try model.createSession(
                    kind: kind,
                    opponent: opponent.trimmingCharacters(in: .whitespacesAndNewlines),
                    movies: movies,
                    metadata: metadata,
                    context: modelContext
                )
                if failedImportCount > 0 {
                    let subject = failedImportCount == 1 ? "Um vídeo" : "\(failedImportCount) vídeos"
                    model.notice = .warning("\(subject) não pôde ser importado. Os demais serão analisados.")
                } else {
                    let subject = AppCopy.importedRecordings(movies.count)
                    model.notice = .success("\(subject). Procurando jogadas.")
                }
                onCreated(session.id)
                dismiss()
            } catch {
                movies.forEach { $0.removeLocalCopy() }
                importIssue = ImportIssue(message: error.localizedDescription)
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
