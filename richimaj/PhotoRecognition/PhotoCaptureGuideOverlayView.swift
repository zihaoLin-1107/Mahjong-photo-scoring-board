import SwiftUI

struct PhotoCaptureGuideOverlayView: View {
    var body: some View {
        GeometryReader { proxy in
            let metrics = PhotoCaptureGuideLayout.metrics(in: proxy.size)
            let boardRect = metrics.boardRect

            ZStack(alignment: .top) {
                Color.clear

                if boardRect.width > 0, boardRect.height > 0 {
                    guideBoard(width: boardRect.width, height: boardRect.height)
                        .frame(width: boardRect.width, height: boardRect.height)
                        .position(x: boardRect.midX, y: boardRect.midY)
                }

            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    private func guideBoard(width: CGFloat, height: CGFloat) -> some View {
        let handRect = PhotoCaptureGuideLayout.handRect
        let openRect = PhotoCaptureGuideLayout.openMeldsRect
        let winningRect = PhotoCaptureGuideLayout.winningRect
        let handHeight = height * handRect.height
        let lowerHeight = height - handHeight
        let leftWidth = width * openRect.width
        let rightWidth = width * winningRect.width
        let topTagY = max(24, height * 0.08)
        let lowerTopTagY = handHeight + max(22, lowerHeight * 0.14)
        let handTagX = width * 0.5
        let meldTagX = leftWidth * 0.5
        let winningTagX = leftWidth + rightWidth * PhotoCaptureGuideLayout.winningTagXRatio
        let winningSlotRect = PhotoCaptureGuideLayout.winningSlotRect
        let winningSlotWidth = rightWidth * winningSlotRect.width
        let winningSlotHeight = lowerHeight * winningSlotRect.height
        let winningSlotX = leftWidth + rightWidth * winningSlotRect.midX
        let winningSlotY = handHeight + lowerHeight * winningSlotRect.midY

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: handHeight))
                path.addLine(to: CGPoint(x: width, y: handHeight))
            }
            .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 6]))

            Path { path in
                path.move(to: CGPoint(x: leftWidth, y: handHeight))
                path.addLine(to: CGPoint(x: leftWidth, y: height))
            }
            .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 6]))

            regionTag(title: "手牌区")
                .position(x: handTagX, y: topTagY)

            regionTag(title: "副露区")
                .position(x: meldTagX, y: lowerTopTagY)

            regionTag(title: "胡牌区")
                .position(x: winningTagX, y: lowerTopTagY)

            winningTileSlot(width: winningSlotWidth, height: winningSlotHeight)
                .position(x: winningSlotX, y: winningSlotY)
        }
    }

    private func regionTag(title: String) -> some View {
        Text(title)
            .font(.headline.weight(.bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
    }

    private func winningTileSlot(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.gray.opacity(0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 2)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.black.opacity(0.10), lineWidth: 1)
                .padding(5)

            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: min(width, height) * 0.18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.82))
                Text("胡牌")
                    .font(.system(size: min(width, height) * 0.14, weight: .bold))
                    .foregroundColor(.white.opacity(0.82))
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        .frame(width: width, height: height)
    }
}
