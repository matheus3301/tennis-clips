@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

/// On-device port of the OpenCV movement gate used by the Python detector.
private struct MotionValidator: Sendable {
    private let width = 270
    private let height = 480
    private let pixelThreshold = 25
    private let shirtHueRange = 18...42

    fileprivate func motionRatio(
        using generator: AVAssetImageGenerator,
        at time: TimeInterval,
        offset: TimeInterval
    ) throws -> Double {
        let requestedTimes = [max(0, time - offset), time, time + offset]
        let frames = try requestedTimes.map { requestedTime in
            let image = try generator.copyCGImage(
                at: CMTime(seconds: requestedTime, preferredTimescale: 600),
                actualTime: nil
            )
            return try rgbaPixels(from: image)
        }
        let roi = playerROI(in: frames[1])
        let before = gaussianBlur(grayPixels(from: frames[0]))
        let after = gaussianBlur(grayPixels(from: frames[2]))

        var changed = 0
        var total = 0
        for y in roi.minY..<roi.maxY {
            for x in roi.minX..<roi.maxX {
                let index = y * width + x
                if abs(Int(before[index]) - Int(after[index])) > pixelThreshold {
                    changed += 1
                }
                total += 1
            }
        }
        return total > 0 ? Double(changed) / Double(total) : 0
    }

    private func rgbaPixels(from image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let created = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard created else { throw MotionValidationError.cannotReadFrame }
        return pixels
    }

    private func playerROI(in pixels: [UInt8]) -> ROI {
        var mask = [Bool](repeating: false, count: width * height)
        let firstPlayerRow = Int((Double(height) * 0.40).rounded())
        for y in firstPlayerRow..<height {
            for x in 0..<width {
                let pixel = (y * width + x) * 4
                let hsv = openCVHSV(
                    red: pixels[pixel],
                    green: pixels[pixel + 1],
                    blue: pixels[pixel + 2]
                )
                mask[y * width + x] = shirtHueRange.contains(hsv.hue)
                    && hsv.saturation >= 90
                    && hsv.value >= 90
            }
        }

        var visited = [Bool](repeating: false, count: mask.count)
        var largest: Component?
        let neighborOffsets = [
            (-1, -1), (0, -1), (1, -1),
            (-1, 0),           (1, 0),
            (-1, 1),  (0, 1),  (1, 1),
        ]

        for start in mask.indices where mask[start] && !visited[start] {
            var queue = [start]
            visited[start] = true
            var cursor = 0
            var component = Component(
                area: 0,
                minX: start % width,
                minY: start / width,
                maxX: start % width,
                maxY: start / width
            )
            while cursor < queue.count {
                let current = queue[cursor]
                cursor += 1
                let x = current % width
                let y = current / width
                component.area += 1
                component.minX = min(component.minX, x)
                component.minY = min(component.minY, y)
                component.maxX = max(component.maxX, x)
                component.maxY = max(component.maxY, y)

                for (dx, dy) in neighborOffsets {
                    let nextX = x + dx
                    let nextY = y + dy
                    guard nextX >= 0, nextX < width, nextY >= 0, nextY < height else { continue }
                    let next = nextY * width + nextX
                    if mask[next], !visited[next] {
                        visited[next] = true
                        queue.append(next)
                    }
                }
            }
            if component.area > 50, component.area > (largest?.area ?? 0) {
                largest = component
            }
        }

        guard let largest else {
            return ROI(
                minX: 0,
                minY: Int((Double(height) * 0.35).rounded()),
                maxX: width,
                maxY: Int((Double(height) * 0.80).rounded())
            )
        }

        // OpenCV stats widths include both edge pixels.
        let boxWidth = largest.maxX - largest.minX + 1
        let boxHeight = largest.maxY - largest.minY + 1
        let centerX = Double(largest.minX) + Double(boxWidth) / 2
        let centerY = Double(largest.minY) + Double(boxHeight) / 2
        let roiWidth = max(90, Double(boxWidth) * 3)
        let roiHeight = max(140, Double(boxHeight) * 2.4)
        return ROI(
            minX: max(0, Int((centerX - roiWidth / 2).rounded())),
            minY: max(Int((Double(height) * 0.35).rounded()), Int((centerY - roiHeight / 2).rounded())),
            maxX: min(width, Int((centerX + roiWidth / 2).rounded())),
            maxY: min(height, Int((centerY + roiHeight / 2).rounded()))
        )
    }

    private func openCVHSV(red: UInt8, green: UInt8, blue: UInt8) -> (hue: Int, saturation: Int, value: Int) {
        // Integer path used by OpenCV's 8-bit RGB/BGR -> HSV conversion.
        let shift = 12
        let half = 1 << (shift - 1)
        let hueRange = 180
        let r = Int(red)
        let g = Int(green)
        let b = Int(blue)
        let maximum = max(r, g, b)
        let minimum = min(r, g, b)
        let difference = maximum - minimum
        guard maximum > 0, difference > 0 else {
            return (0, 0, maximum)
        }

        let saturationDivisor = Int(
            (Double(255 << shift) / Double(maximum)).rounded(.toNearestOrEven)
        )
        let saturation = (difference * saturationDivisor + half) >> shift
        let hueDivisor = Int(
            (Double(hueRange << shift) / Double(6 * difference)).rounded(.toNearestOrEven)
        )
        let numerator: Int
        if maximum == r {
            numerator = g - b
        } else if maximum == g {
            numerator = b - r + 2 * difference
        } else {
            numerator = r - g + 4 * difference
        }
        var hue = (numerator * hueDivisor + half) >> shift
        if hue < 0 { hue += hueRange }
        return (min(hueRange - 1, hue), min(255, saturation), maximum)
    }

    private func grayPixels(from rgba: [UInt8]) -> [UInt8] {
        var gray = [UInt8](repeating: 0, count: width * height)
        for index in gray.indices {
            let pixel = index * 4
            let weighted = 77 * Int(rgba[pixel])
                + 150 * Int(rgba[pixel + 1])
                + 29 * Int(rgba[pixel + 2])
            gray[index] = UInt8((weighted + 128) >> 8)
        }
        return gray
    }

    private func gaussianBlur(_ source: [UInt8]) -> [UInt8] {
        let kernel = [1, 4, 6, 4, 1]
        var horizontal = [UInt8](repeating: 0, count: source.count)
        var destination = horizontal
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0
                for offset in -2...2 {
                    sum += kernel[offset + 2] * Int(source[y * width + reflected(x + offset, limit: width)])
                }
                horizontal[y * width + x] = UInt8((sum + 8) / 16)
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0
                for offset in -2...2 {
                    sum += kernel[offset + 2] * Int(horizontal[reflected(y + offset, limit: height) * width + x])
                }
                destination[y * width + x] = UInt8((sum + 8) / 16)
            }
        }
        return destination
    }

    private func reflected(_ rawIndex: Int, limit: Int) -> Int {
        if rawIndex < 0 { return -rawIndex }
        if rawIndex >= limit { return 2 * limit - rawIndex - 2 }
        return rawIndex
    }

    private struct ROI {
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int
    }

    private struct Component {
        var area: Int
        var minX: Int
        var minY: Int
        var maxX: Int
        var maxY: Int
    }
}

private enum MotionValidationError: Error {
    case cannotReadFrame
}

/// Reuses one AVFoundation frame generator for all candidates in a training.
/// Actor isolation prevents concurrent access to AVAssetImageGenerator.
public actor MotionValidationSession {
    private let generator: AVAssetImageGenerator
    private let validator = MotionValidator()

    public init(asset: AVAsset) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        self.generator = generator
    }

    public func motionRatio(at time: TimeInterval, offset: TimeInterval) throws -> Double {
        try validator.motionRatio(using: generator, at: time, offset: offset)
    }
}
