import Foundation
import CoreGraphics

struct PostProcessDetectedTile: Hashable {
    var boundingBox: CGRect
    var candidate: PhotoTileToken?
    var candidates: [PhotoTileToken]

    var confidence: Double {
        candidate?.confidence ?? candidates.first?.confidence ?? 0
    }

    var tileName: String? {
        candidate?.displayName
    }
}

struct HandRegionPostProcessResult {
    var tiles: [PostProcessDetectedTile]
    var warnings: [String]
}

struct OpenMeldRegionPostProcessResult {
    var tiles: [PostProcessDetectedTile]
    var groupedTiles: [[PostProcessDetectedTile]]
    var kongCount: Int
    var warnings: [String]
}

struct WinningRegionPostProcessResult {
    var tile: PostProcessDetectedTile?
    var warnings: [String]
}

struct PhotoRecognitionPostProcessResult {
    var hand: HandRegionPostProcessResult
    var openMelds: OpenMeldRegionPostProcessResult
    var winning: WinningRegionPostProcessResult
    var isStructurallyValid: Bool
    var warnings: [String]
}

struct HandRegionPostProcessor {
    func process(_ tiles: [PostProcessDetectedTile]) -> HandRegionPostProcessResult {
        var warnings: [String] = []
        let filtered = filterLikelyTileRects(tiles)
        let deduped = removeHighlyOverlappingTiles(filtered)
        let sorted = deduped.sorted { $0.boundingBox.midX < $1.boundingBox.midX }

        if deduped.count != tiles.count {
            warnings.append("手牌区已过滤尺寸异常或重叠过高的候选框。")
        }

        if sorted.count > 13 {
            warnings.append("手牌区超过 13 张，已按规则裁剪到 13 张。")
        }

        return HandRegionPostProcessResult(
            tiles: Array(sorted.prefix(13)),
            warnings: warnings
        )
    }

    private func filterLikelyTileRects(_ tiles: [PostProcessDetectedTile]) -> [PostProcessDetectedTile] {
        guard !tiles.isEmpty else { return [] }
        let widths = tiles.map { $0.boundingBox.width }.sorted()
        let heights = tiles.map { $0.boundingBox.height }.sorted()
        let medianWidth = widths[widths.count / 2]
        let medianHeight = heights[heights.count / 2]

        return tiles.filter { tile in
            let width = tile.boundingBox.width
            let height = tile.boundingBox.height
            let ratio = width / max(height, 0.0001)
            let widthOK = width >= medianWidth * 0.55 && width <= medianWidth * 1.8
            let heightOK = height >= medianHeight * 0.55 && height <= medianHeight * 1.8
            let ratioOK = ratio >= 0.18 && ratio <= 0.95
            return widthOK && heightOK && ratioOK
        }
    }

    private func removeHighlyOverlappingTiles(_ tiles: [PostProcessDetectedTile]) -> [PostProcessDetectedTile] {
        let sorted = tiles.sorted { $0.confidence > $1.confidence }
        var kept: [PostProcessDetectedTile] = []

        for tile in sorted {
            if kept.contains(where: { iou($0.boundingBox, tile.boundingBox) > 0.55 }) {
                continue
            }
            kept.append(tile)
        }
        return kept
    }
}

struct OpenMeldRegionPostProcessor {
    func process(_ tiles: [PostProcessDetectedTile]) -> OpenMeldRegionPostProcessResult {
        var warnings: [String] = []
        let filtered = filterLikelyTileRects(tiles)
        let deduped = removeHighlyOverlappingTiles(filtered)
        let sorted = deduped.sorted { $0.boundingBox.midX < $1.boundingBox.midX }
        let kongCount = inferredKongCount(from: sorted)
        let validCount = isValidOpenMeldTileCount(sorted.count, kongCount: kongCount)

        if deduped.count != tiles.count {
            warnings.append("副露区已过滤尺寸异常或重叠过高的候选框。")
        }
        if !validCount {
            warnings.append("副露区张数暂未完全满足 3 的倍数或杠子规则。")
        }

        return OpenMeldRegionPostProcessResult(
            tiles: sorted,
            groupedTiles: groupTiles(sorted, kongCount: kongCount),
            kongCount: kongCount,
            warnings: warnings
        )
    }

    private func inferredKongCount(from tiles: [PostProcessDetectedTile]) -> Int {
        let counts = Dictionary(grouping: tiles.compactMap(\.tileName), by: { $0 }).mapValues(\.count)
        return counts.values.filter { $0 >= 4 }.count
    }

    private func isValidOpenMeldTileCount(_ count: Int, kongCount: Int) -> Bool {
        if count == 0 { return true }
        if count % 3 == 0 && count <= 12 { return true }
        return kongCount > 0 && ((count - kongCount) % 3 == 0)
    }

    private func groupTiles(_ tiles: [PostProcessDetectedTile], kongCount: Int) -> [[PostProcessDetectedTile]] {
        guard !tiles.isEmpty else { return [] }
        var groups: [[PostProcessDetectedTile]] = []
        var current: [PostProcessDetectedTile] = []
        var lastX: CGFloat?
        let averageWidth = tiles.map(\.boundingBox.width).reduce(0, +) / CGFloat(max(tiles.count, 1))
        let gapThreshold = averageWidth * 0.9

        for tile in tiles {
            if let lastX, tile.boundingBox.minX - lastX > gapThreshold, !current.isEmpty {
                groups.append(current)
                current = []
            }
            current.append(tile)
            lastX = tile.boundingBox.maxX
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups
    }

    private func filterLikelyTileRects(_ tiles: [PostProcessDetectedTile]) -> [PostProcessDetectedTile] {
        guard !tiles.isEmpty else { return [] }
        let widths = tiles.map { $0.boundingBox.width }.sorted()
        let heights = tiles.map { $0.boundingBox.height }.sorted()
        let medianWidth = widths[widths.count / 2]
        let medianHeight = heights[heights.count / 2]

        return tiles.filter { tile in
            let width = tile.boundingBox.width
            let height = tile.boundingBox.height
            let ratio = width / max(height, 0.0001)
            let widthOK = width >= medianWidth * 0.45 && width <= medianWidth * 2.0
            let heightOK = height >= medianHeight * 0.45 && height <= medianHeight * 2.0
            let ratioOK = ratio >= 0.18 && ratio <= 1.05
            return widthOK && heightOK && ratioOK
        }
    }

    private func removeHighlyOverlappingTiles(_ tiles: [PostProcessDetectedTile]) -> [PostProcessDetectedTile] {
        let sorted = tiles.sorted { $0.confidence > $1.confidence }
        var kept: [PostProcessDetectedTile] = []

        for tile in sorted {
            if kept.contains(where: { iou($0.boundingBox, tile.boundingBox) > 0.55 }) {
                continue
            }
            kept.append(tile)
        }
        return kept
    }
}

struct WinningRegionPostProcessor {
    func process(_ tiles: [PostProcessDetectedTile]) -> WinningRegionPostProcessResult {
        guard !tiles.isEmpty else {
            return WinningRegionPostProcessResult(tile: nil, warnings: [])
        }

        if tiles.count == 1 {
            return WinningRegionPostProcessResult(tile: tiles[0], warnings: [])
        }

        let center = CGPoint(x: 0.5, y: 0.5)
        let best = tiles.max { lhs, rhs in
            score(lhs, center: center) < score(rhs, center: center)
        }
        return WinningRegionPostProcessResult(
            tile: best,
            warnings: ["胡牌区检测出多张候选，已按中心位置和置信度保留 1 张。"]
        )
    }

    private func score(_ tile: PostProcessDetectedTile, center: CGPoint) -> Double {
        let dx = Double(tile.boundingBox.midX - center.x)
        let dy = Double(tile.boundingBox.midY - center.y)
        let distancePenalty = sqrt(dx * dx + dy * dy)
        return tile.confidence - distancePenalty * 0.35
    }
}

struct PhotoRecognitionPostProcessor {
    private let handProcessor = HandRegionPostProcessor()
    private let openMeldProcessor = OpenMeldRegionPostProcessor()
    private let winningProcessor = WinningRegionPostProcessor()

    func process(regions: [PhotoCaptureRegion: [PostProcessDetectedTile]]) -> PhotoRecognitionPostProcessResult {
        let hand = handProcessor.process(regions[.hand] ?? [])
        let openMelds = openMeldProcessor.process(regions[.openMelds] ?? [])
        let winning = winningProcessor.process(regions[.winning] ?? [])

        var warnings = hand.warnings + openMelds.warnings + winning.warnings
        let winningCount = winning.tile == nil ? 0 : 1
        let combinedCount = hand.tiles.count + openMelds.tiles.count

        var isStructurallyValid = true
        if hand.tiles.count > 13 {
            isStructurallyValid = false
            warnings.append("手牌区超过 13 张。")
        }
        if winningCount != 1 {
            isStructurallyValid = false
            warnings.append("胡牌区必须且只能有 1 张。")
        }
        if !(13...17).contains(combinedCount) {
            isStructurallyValid = false
            warnings.append("当前手牌区与副露区合计应在 13 到 17 张之间。")
        }

        return PhotoRecognitionPostProcessResult(
            hand: hand,
            openMelds: openMelds,
            winning: winning,
            isStructurallyValid: isStructurallyValid,
            warnings: warnings
        )
    }
}

private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let intersection = a.intersection(b)
    guard !intersection.isNull else { return 0 }
    let interArea = intersection.width * intersection.height
    let union = (a.width * a.height) + (b.width * b.height) - interArea
    guard union > 0 else { return 0 }
    return interArea / union
}
