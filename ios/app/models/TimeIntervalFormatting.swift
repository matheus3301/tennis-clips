import Foundation

extension TimeInterval {
    var shortDuration: String {
        let total = Int(max(self, 0).rounded())
        let seconds = String(total % 60).leftPadded(to: 2, with: "0")
        return "\(total / 60):\(seconds)"
    }

    var spokenDuration: String {
        let total = Int(max(self, 0).rounded())
        let minutes = total / 60
        let seconds = total % 60
        let minuteText = minutes == 1 ? "1 minuto" : "\(minutes) minutos"
        let secondText = seconds == 1 ? "1 segundo" : "\(seconds) segundos"
        return switch (minutes, seconds) {
        case (0, _): secondText
        case (_, 0): minuteText
        default: minuteText + " e " + secondText
        }
    }
}

private extension String {
    func leftPadded(to length: Int, with character: Character) -> String {
        String(repeating: character, count: max(0, length - count)) + self
    }
}
