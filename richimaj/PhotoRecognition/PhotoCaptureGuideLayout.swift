import CoreGraphics

struct PhotoCaptureGuideLayout {
    static let separatorX: CGFloat = 0.72
    static let separatorY: CGFloat = 0.5

    static let handRect = CGRect(x: 0, y: 0, width: 1, height: separatorY)
    static let openMeldsRect = CGRect(x: 0, y: separatorY, width: separatorX, height: 1 - separatorY)
    static let winningRect = CGRect(x: separatorX, y: separatorY, width: 1 - separatorX, height: 1 - separatorY)

    // Winning-slot guide inside winning area, derived from the user's approved mock.
    static let winningSlotRect = CGRect(x: 0.28, y: 0.42, width: 0.37, height: 0.41)
    static let winningTagXRatio: CGFloat = 0.37

    struct Metrics {
        var previewRect: CGRect
        var boardRect: CGRect
        var controlsRect: CGRect
    }

    static func metrics(in containerSize: CGSize) -> Metrics {
        let isLandscape = containerSize.width > containerSize.height

        if isLandscape {
            let outerInset = min(containerSize.width, containerSize.height) * 0.02
            let controlsWidth = max(112, containerSize.width * 0.16)
            let previewRect = CGRect(
                x: outerInset,
                y: outerInset,
                width: max(0, containerSize.width - controlsWidth - outerInset * 2),
                height: max(0, containerSize.height - outerInset * 2)
            )
            let controlsRect = CGRect(
                x: previewRect.maxX,
                y: 0,
                width: containerSize.width - previewRect.maxX,
                height: containerSize.height
            )

            return Metrics(
                previewRect: previewRect,
                boardRect: previewRect,
                controlsRect: controlsRect
            )
        }

        let controlAreaHeight = containerSize.height * 0.26
        let previewHeight = max(0, containerSize.height - controlAreaHeight)
        let horizontalInset = containerSize.width * 0.03
        let topInset = containerSize.height * 0.012
        let bottomInset = previewHeight * 0.04
        let previewRect = CGRect(
            x: horizontalInset,
            y: topInset,
            width: max(0, containerSize.width - horizontalInset * 2),
            height: max(0, previewHeight - topInset - bottomInset)
        )

        return Metrics(
            previewRect: previewRect,
            boardRect: previewRect,
            controlsRect: CGRect(
                x: 0,
                y: previewRect.maxY,
                width: containerSize.width,
                height: containerSize.height - previewRect.maxY
            )
        )
    }
}
