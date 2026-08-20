import SwiftData
import SwiftUI

struct ClipTrimSelection: Identifiable {
    let clip: RallyClip
    let sourceURL: URL
    let videoDuration: TimeInterval

    var id: UUID { clip.id }
}

struct ClipTrimView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let selection: ClipTrimSelection

    @State private var start: TimeInterval
    @State private var end: TimeInterval

    init(selection: ClipTrimSelection) {
        self.selection = selection
        _start = State(initialValue: selection.clip.start)
        _end = State(initialValue: selection.clip.end)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    RallyPlayerView(url: selection.sourceURL, start: start, end: end)
                        .frame(height: 330)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(spacing: 18) {
                        trimControl(
                            title: "Início",
                            value: $start,
                            range: lowerBound...max(lowerBound, end - minimumDuration)
                        )
                        trimControl(
                            title: "Fim",
                            value: $end,
                            range: min(upperBound, start + minimumDuration)...upperBound
                        )
                    }
                    .padding(18)
                    .background(AppPalette.courtMist.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))

                    Text("Duração: \((end - start).shortDuration)")
                        .font(.footnote.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 16)
                }
                .padding(20)
            }
            .background(AppPalette.chalk.ignoresSafeArea())
            .navigationTitle("Ajustar corte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save)
                }
            }
        }
    }

    private var minimumDuration: TimeInterval { 0.5 }
    private var lowerBound: TimeInterval { max(0, selection.clip.start - 3) }
    private var upperBound: TimeInterval {
        min(selection.videoDuration, selection.clip.end + 3)
    }

    private func trimControl(
        title: String,
        value: Binding<TimeInterval>,
        range: ClosedRange<TimeInterval>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(value.wrappedValue.shortDuration)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.1)
        }
    }

    private func save() {
        if model.updateClipBounds(
            selection.clip,
            start: start,
            end: end,
            context: modelContext
        ) {
            dismiss()
        }
    }
}

struct ReviewActionButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.ink.opacity(0.62))
                }
            }
        }
        .accessibilityLabel(label)
    }
}
