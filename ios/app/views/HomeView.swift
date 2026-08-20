import PhotosUI
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedItem: PhotosPickerItem?
    @State private var isLoadingSelection = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("TENNIS CLIPS")
                    .font(.caption.weight(.bold))
                    .tracking(2.4)
                    .foregroundStyle(AppPalette.court)
                    .padding(.top, 22)

                Text("Treino longo.\nSó as jogadas.")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .tracking(-1.8)
                    .foregroundStyle(AppPalette.ink)
                    .padding(.top, 22)

                Text("Escolha uma gravação. O iPhone encontra as batidas e monta um vídeo fluido — sem enviar nada para a internet.")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(AppPalette.ink.opacity(0.68))
                    .lineSpacing(4)
                    .padding(.top, 18)

                CourtCard()
                    .padding(.top, 34)

                PhotosPicker(selection: $selectedItem, matching: .videos) {
                    HStack(spacing: 12) {
                        if isLoadingSelection {
                            ProgressView().tint(AppPalette.chalk)
                        } else {
                            Image(systemName: "video.badge.plus")
                        }
                        Text(isLoadingSelection ? "Abrindo vídeo" : "Escolher treino")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .foregroundStyle(AppPalette.chalk)
                    .background(AppPalette.court, in: RoundedRectangle(cornerRadius: 18))
                }
                .disabled(isLoadingSelection)
                .padding(.top, 26)

                Label("Processamento 100% no aparelho", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppPalette.ink.opacity(0.56))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            isLoadingSelection = true
            Task {
                defer { isLoadingSelection = false }
                do {
                    if let movie = try await item.loadTransferable(type: ImportedMovie.self) {
                        model.process(videoAt: movie.url)
                    }
                } catch {
                    model.reportFailure(error)
                }
            }
        }
    }
}

private struct CourtCard: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(AppPalette.courtBlue)
            CourtLines()
                .stroke(AppPalette.line, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .padding(24)
            VStack {
                HStack {
                    Text("RALLY MODE")
                        .font(.caption2.weight(.black))
                        .tracking(1.6)
                    Spacer()
                    Circle()
                        .fill(AppPalette.ball)
                        .frame(width: 16, height: 16)
                        .shadow(color: AppPalette.ball.opacity(0.4), radius: 8)
                }
                Spacer()
                HStack(alignment: .bottom) {
                    Text("1.2s")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                    Text("antes")
                        .font(.caption.weight(.bold))
                        .padding(.bottom, 5)
                    Spacer()
                    Text("2.6s")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                    Text("depois")
                        .font(.caption.weight(.bold))
                        .padding(.bottom, 5)
                }
            }
            .foregroundStyle(AppPalette.line)
            .padding(22)
        }
        .frame(height: 210)
        .shadow(color: AppPalette.court.opacity(0.14), radius: 24, y: 14)
    }
}

private struct CourtLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addRect(rect.insetBy(dx: rect.width * 0.19, dy: rect.height * 0.25))
        return path
    }
}
