import CoreGraphics

enum PhotoCaptureRegion: CaseIterable, Hashable {
    case hand
    case openMelds
    case winning

    var outputKey: String {
        switch self {
        case .hand:
            return "hand"
        case .openMelds:
            return "openMelds"
        case .winning:
            return "winning"
        }
    }

    var title: String {
        switch self {
        case .hand:
            return "手牌区"
        case .openMelds:
            return "副露区"
        case .winning:
            return "胡牌区"
        }
    }

    var normalizedRect: CGRect {
        switch self {
        case .hand:
            return PhotoCaptureGuideLayout.handRect
        case .openMelds:
            return PhotoCaptureGuideLayout.openMeldsRect
        case .winning:
            return PhotoCaptureGuideLayout.winningRect
        }
    }
}

struct PhotoRecognitionRegionImage {
    var region: PhotoCaptureRegion
    var image: CGImage

    var imageSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }
}

struct PhotoRecognitionSegmentedImage {
    var baseImageSize: CGSize
    var regions: [PhotoRecognitionRegionImage]

    func image(for region: PhotoCaptureRegion) -> CGImage? {
        regions.first(where: { $0.region == region })?.image
    }
}

struct PhotoRecognitionImageSegmenter {
    func normalizedLandscapeImage(from cgImage: CGImage) -> CGImage {
        if cgImage.width < cgImage.height {
            return cgImage.rotated270() ?? cgImage
        }
        return cgImage
    }

    func segment(_ cgImage: CGImage) -> PhotoRecognitionSegmentedImage {
        let landscapeImage = normalizedLandscapeImage(from: cgImage)
        let regionRects = dynamicRegionRects()
        let regions = PhotoCaptureRegion.allCases.compactMap { region -> PhotoRecognitionRegionImage? in
            guard let rect = regionRects[region],
                  let cropped = crop(cgImage: landscapeImage, normalizedRect: rect) else {
                return nil
            }
            return PhotoRecognitionRegionImage(region: region, image: cropped)
        }

        return PhotoRecognitionSegmentedImage(
            baseImageSize: CGSize(width: landscapeImage.width, height: landscapeImage.height),
            regions: regions
        )
    }

    private func dynamicRegionRects() -> [PhotoCaptureRegion: CGRect] {
        return [
            .hand: PhotoCaptureGuideLayout.handRect,
            .openMelds: PhotoCaptureGuideLayout.openMeldsRect,
            .winning: PhotoCaptureGuideLayout.winningRect,
        ]
    }

    private func crop(cgImage: CGImage, normalizedRect: CGRect) -> CGImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let rect = CGRect(
            x: normalizedRect.minX * width,
            y: normalizedRect.minY * height,
            width: normalizedRect.width * width,
            height: normalizedRect.height * height
        ).integral

        guard rect.width > 0, rect.height > 0 else { return nil }
        return cgImage.cropping(to: rect)
    }
}
