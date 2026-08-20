import SwiftData
import SwiftUI

struct AppInformationView: View {
    @Environment(AppModel.self) private var model
    @Query private var sessions: [TennisSession]

    @AppStorage("appAppearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage("exportQuality") private var exportQualityRaw = ExportQuality.high.rawValue
    @State private var storageBytes: Int64 = 0

    var body: some View {
        Form {
            Section("Armazenamento") {
                LabeledContent {
                    Text(storageDescription)
                        .monospacedDigit()
                } label: {
                    Label("Uso local", systemImage: "internaldrive")
                }

                Text("Inclui as gravações importadas, jogadas salvas e vídeos finais.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Biblioteca") {
                LabeledContent("Sessões", value: String(sessions.count))
                LabeledContent("Gravações", value: String(recordingCount))
                LabeledContent("Jogadas", value: String(clipCount))
            }

            Section("Privacidade") {
                Label("O processamento acontece no iPhone.", systemImage: "iphone.and.arrow.forward")
                Label("As mídias do app são excluídas do backup.", systemImage: "icloud.slash")
            }

            Section("Suporte") {
                ShareLink(item: diagnosticReport) {
                    Label("Compartilhar diagnóstico", systemImage: "doc.text")
                }
                Text("O relatório contém apenas versão, sistema e contagens locais — nunca nomes ou vídeos.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Sobre") {
                LabeledContent("Versão", value: "\(version) (\(build))")
            }
        }
        .navigationTitle("Informações")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            storageBytes = await model.storageUsageBytes()
        }
    }

    private var recordingCount: Int {
        sessions.reduce(0) { $0 + $1.videos.count }
    }

    private var clipCount: Int {
        sessions.reduce(0) { $0 + $1.clips.count }
    }

    private var storageDescription: String {
        ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "desconhecida"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "desconhecido"
    }

    private var diagnosticReport: String {
        let statuses = Dictionary(grouping: sessions, by: \.statusRaw)
            .map { "\($0.key)=\($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        return """
        Diagnóstico Tennis Clips
        Versão: \(version) (\(build))
        Sistema: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Sessões: \(sessions.count)
        Gravações: \(recordingCount)
        Jogadas: \(clipCount)
        Estados: \(statuses.isEmpty ? "nenhum" : statuses)
        Armazenamento local: \(storageDescription)
        Qualidade de exportação: \(exportQualityRaw)
        Aparência: \(appearanceRaw)
        """
    }
}
