import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("appAppearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage("exportQuality") private var exportQualityRaw = ExportQuality.high.rawValue
    @AppStorage("titleStyle") private var titleStyleRaw = TitleStyle.standard.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Aparência") {
                    Picker("Tema", selection: $appearanceRaw) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance.rawValue)
                        }
                    }
                }

                Section("Vídeo final") {
                    Picker("Qualidade", selection: $exportQualityRaw) {
                        ForEach(ExportQuality.allCases) { quality in
                            Text(quality.title).tag(quality.rawValue)
                        }
                    }
                    Text(exportQualityDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Apple Intelligence") {
                    Picker("Estilo dos títulos", selection: $titleStyleRaw) {
                        ForEach(TitleStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    Text(titleStyleDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Aplicativo") {
                    NavigationLink {
                        AppInformationView()
                    } label: {
                        Label("Informações", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private var exportQualityDescription: String {
        exportQualityRaw == ExportQuality.compact.rawValue
            ? "Usa H.264/AAC em qualidade média para ocupar menos espaço."
            : "Preserva a maior qualidade disponível em H.264/AAC."
    }

    private var titleStyleDescription: String {
        (TitleStyle(rawValue: titleStyleRaw) ?? .standard).description
    }

}
