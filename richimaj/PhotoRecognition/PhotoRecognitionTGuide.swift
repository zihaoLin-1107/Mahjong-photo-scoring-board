import CoreGraphics

struct PhotoRecognitionGuideSplit {
    var separatorX: CGFloat
    var separatorY: CGFloat

    var handRect: CGRect {
        CGRect(x: 0, y: 0, width: 1, height: separatorY)
    }

    var openMeldsRect: CGRect {
        CGRect(x: 0, y: separatorY, width: separatorX, height: 1 - separatorY)
    }

    var winningRect: CGRect {
        CGRect(x: separatorX, y: separatorY, width: 1 - separatorX, height: 1 - separatorY)
    }
}

struct PhotoRecognitionOrientationResolution {
    var image: CGImage
    var split: PhotoRecognitionGuideSplit
}

struct TGuideDetector {
    func detect(in cgImage: CGImage) -> PhotoRecognitionGuideSplit? {
        guard let pixelData = cgImage.rgbaPixelData() else { return nil }

        let defaultSplit = PhotoRecognitionGuideSplit(separatorX: 0.58, separatorY: 0.5)
        let separatorX = detectWinningSeparatorX(in: cgImage, pixelData: pixelData) ?? defaultSplit.separatorX
        let separatorY = detectHandSeparatorY(in: cgImage, pixelData: pixelData, separatorX: separatorX) ?? defaultSplit.separatorY

        return PhotoRecognitionGuideSplit(
            separatorX: min(max(separatorX, 0.5), 0.75),
            separatorY: min(max(separatorY, 0.25), 0.75)
        )
    }

    private func detectWinningSeparatorX(in cgImage: CGImage, pixelData: [UInt8]) -> CGFloat? {
        let width = cgImage.width
        let height = cgImage.height
        let startY = Int(Double(height) * 0.5)
        let expectedX = Int(Double(width) * 0.58)
        let searchRadius = max(50, Int(Double(width) * 0.14))
        let searchStart = max(0, expectedX - searchRadius)
        let searchEnd = min(width - 1, expectedX + searchRadius)
        var bestX: Int?
        var bestScore: Double = 0

        for x in searchStart...searchEnd {
            var whiteCount = 0
            var sampleCount = 0
            var segmentCount = 0
            var inRun = false

            for y in stride(from: startY, to: height, by: 3) {
                let offset = ((y * width) + x) * 4
                let r = Int(pixelData[offset])
                let g = Int(pixelData[offset + 1])
                let b = Int(pixelData[offset + 2])
                let isWhite = r > 210 && g > 210 && b > 210 && abs(r - g) < 28 && abs(g - b) < 28
                sampleCount += 1
                if isWhite {
                    whiteCount += 1
                    if !inRun {
                        inRun = true
                        segmentCount += 1
                    }
                } else {
                    inRun = false
                }
            }

            guard sampleCount > 0 else { continue }
            let coverage = Double(whiteCount) / Double(sampleCount)
            let distancePenalty = Double(abs(x - expectedX)) / Double(searchRadius)
            let segmentationBonus = min(Double(segmentCount), 8.0) / 8.0
            let score = coverage * 0.8 + segmentationBonus * 0.4 - distancePenalty * 0.25

            if score > bestScore && coverage > 0.08 && segmentCount >= 4 {
                bestScore = score
                bestX = x
            }
        }

        guard let bestX else { return nil }
        return CGFloat(bestX) / CGFloat(width)
    }

    private func detectHandSeparatorY(in cgImage: CGImage, pixelData: [UInt8], separatorX: CGFloat) -> CGFloat? {
        let width = cgImage.width
        let height = cgImage.height
        let expectedY = Int(Double(height) * 0.5)
        let searchRadius = max(50, Int(Double(height) * 0.18))
        let searchStart = max(0, expectedY - searchRadius)
        let searchEnd = min(height - 1, expectedY + searchRadius)
        let maxX = max(1, Int(CGFloat(width) * separatorX))
        var bestY: Int?
        var bestScore: Double = 0

        for y in searchStart...searchEnd {
            var whiteCount = 0
            var sampleCount = 0
            var segmentCount = 0
            var inRun = false

            for x in stride(from: 0, to: maxX, by: 3) {
                let offset = ((y * width) + x) * 4
                let r = Int(pixelData[offset])
                let g = Int(pixelData[offset + 1])
                let b = Int(pixelData[offset + 2])
                let isWhite = r > 210 && g > 210 && b > 210 && abs(r - g) < 28 && abs(g - b) < 28
                sampleCount += 1
                if isWhite {
                    whiteCount += 1
                    if !inRun {
                        inRun = true
                        segmentCount += 1
                    }
                } else {
                    inRun = false
                }
            }

            guard sampleCount > 0 else { continue }
            let coverage = Double(whiteCount) / Double(sampleCount)
            let distancePenalty = Double(abs(y - expectedY)) / Double(searchRadius)
            let segmentationBonus = min(Double(segmentCount), 10.0) / 10.0
            let score = coverage * 0.8 + segmentationBonus * 0.35 - distancePenalty * 0.2

            if score > bestScore && coverage > 0.08 && segmentCount >= 4 {
                bestScore = score
                bestY = y
            }
        }

        guard let bestY else { return nil }
        return CGFloat(bestY) / CGFloat(height)
    }
}

struct RegionCropValidator {
    func score(split: PhotoRecognitionGuideSplit) -> Double? {
        let handArea = Double(split.handRect.width * split.handRect.height)
        let openArea = Double(split.openMeldsRect.width * split.openMeldsRect.height)
        let winningArea = Double(split.winningRect.width * split.winningRect.height)

        guard handArea > openArea, openArea > winningArea else { return nil }

        let separatorXPenalty = abs(Double(split.separatorX - 0.58))
        let separatorYPenalty = abs(Double(split.separatorY - 0.5))
        return handArea * 2.0 - winningArea * 1.5 - separatorXPenalty * 0.4 - separatorYPenalty * 0.4
    }
}

struct RegionOrientationResolver {
    private let guideDetector = TGuideDetector()
    private let validator = RegionCropValidator()

    func resolve(for cgImage: CGImage) -> PhotoRecognitionOrientationResolution? {
        let candidates = [cgImage, cgImage.rotated90(), cgImage.rotated180(), cgImage.rotated270()].compactMap { $0 }
        var best: PhotoRecognitionOrientationResolution?
        var bestScore = -Double.infinity

        for candidate in candidates {
            guard let split = guideDetector.detect(in: candidate),
                  let score = validator.score(split: split) else {
                continue
            }

            if score > bestScore {
                bestScore = score
                best = PhotoRecognitionOrientationResolution(image: candidate.rotated180() ?? candidate, split: split)
            }
        }

        return best
    }
}

extension CGImage {
    func rgbaPixelData() -> [UInt8]? {
        let width = self.width
        let height = self.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    func rotated90() -> CGImage? {
        rotateCanvas(width: height, height: width) { context in
            context.translateBy(x: CGFloat(height) / 2, y: CGFloat(width) / 2)
            context.rotate(by: .pi / 2)
            context.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)
            context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func rotated180() -> CGImage? {
        rotateCanvas(width: width, height: height) { context in
            context.translateBy(x: CGFloat(width), y: CGFloat(height))
            context.rotate(by: .pi)
            context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func rotated270() -> CGImage? {
        rotateCanvas(width: height, height: width) { context in
            context.translateBy(x: CGFloat(height) / 2, y: CGFloat(width) / 2)
            context.rotate(by: -.pi / 2)
            context.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)
            context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func rotateCanvas(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage? {
        let colorSpace = colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        draw(context)
        return context.makeImage()
    }
}
