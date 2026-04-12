import Foundation
import Vision
import CoreGraphics
import ImageIO
import UIKit

struct LocalVisionPhotoRecognitionService: PhotoRecognitionService {
    private let fallbackService: MockPhotoRecognitionService
    private let tileClassifier: any SingleTileClassifier
    private let tileDetector: any TileDetector
    private let imageSegmenter: PhotoRecognitionImageSegmenter
    private let postProcessor: PhotoRecognitionPostProcessor
    
    init(
        fallbackService: MockPhotoRecognitionService = MockPhotoRecognitionService(),
        tileClassifier: any SingleTileClassifier = CoreMLSingleTileClassifier(),
        tileDetector: any TileDetector = CoreMLObjectTileDetector(),
        imageSegmenter: PhotoRecognitionImageSegmenter = PhotoRecognitionImageSegmenter(),
        postProcessor: PhotoRecognitionPostProcessor = PhotoRecognitionPostProcessor()
    ) {
        self.fallbackService = fallbackService
        self.tileClassifier = tileClassifier
        self.tileDetector = tileDetector
        self.imageSegmenter = imageSegmenter
        self.postProcessor = postProcessor
    }
    
    func recognize(request: PhotoRecognitionRequest) async throws -> PhotoRecognitionResult {
        switch request.source {
        case .sample, .camera, .photoLibrary:
            guard let imageData = request.imageData else {
                throw PhotoRecognitionServiceError.unsupportedInput
            }
            
            let analysis = try analyzeImageData(imageData)
            if let classifiedResult = classifyTiles(from: analysis, source: request.source, hint: request.handPatternHint) {
                return classifiedResult
            }
            return failedRecognitionResult(from: analysis, source: request.source)
        }
    }
    
    private func analyzeImageData(_ imageData: Data) throws -> LocalImageAnalysis {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw PhotoRecognitionServiceError.unsupportedInput
        }

        let segmentedImage = imageSegmenter.segment(cgImage)
        let detectedRegions = detectRegions(in: segmentedImage)
        let filteredRegions = applyWinningReferenceFilter(to: detectedRegions)
        let regionAnalyses = classifyRegions(filteredRegions)
        let allDetectedTiles = regionAnalyses.flatMap(\.detectedTiles)
        let postProcessed = buildPostProcessedAnalysis(from: regionAnalyses)
        
        return LocalImageAnalysis(
            imageSize: segmentedImage.baseImageSize,
            detectedTiles: allDetectedTiles,
            regionAnalyses: regionAnalyses,
            postProcessed: postProcessed
        )
    }

    private func detectRegions(in segmentedImage: PhotoRecognitionSegmentedImage) -> [LocalRegionAnalysis] {
        segmentedImage.regions.compactMap { regionImage in
            let detectedTiles = detectTiles(in: regionImage.image)
            return LocalRegionAnalysis(
                region: regionImage.region,
                regionImage: regionImage.image,
                imageSize: regionImage.imageSize,
                detectedTiles: detectedTiles
            )
        }
    }

    private func detectTiles(in cgImage: CGImage) -> [LocalDetectedTile] {
        tileDetector.detectTiles(in: cgImage).map { detection in
            LocalDetectedTile(
                boundingBox: detection.boundingBox,
                detectionConfidence: detection.confidence,
                candidate: nil
            )
        }
    }

    private func classifyRegions(_ regions: [LocalRegionAnalysis]) -> [LocalRegionAnalysis] {
        regions.map { region in
            LocalRegionAnalysis(
                region: region.region,
                regionImage: region.regionImage,
                imageSize: region.imageSize,
                detectedTiles: classifyDetectedTiles(region.detectedTiles, in: region.regionImage)
            )
        }
    }

    private func classifyDetectedTiles(_ detections: [LocalDetectedTile], in cgImage: CGImage) -> [LocalDetectedTile] {
        detections.compactMap { tile -> LocalDetectedTile? in
            guard let croppedImage = crop(cgImage: cgImage, boundingBox: tile.boundingBox) else {
                return tile
            }
            
            let classification = tileClassifier.classifyTile(in: croppedImage)
            return LocalDetectedTile(
                boundingBox: tile.boundingBox,
                detectionConfidence: tile.detectionConfidence,
                candidate: classification.bestMatch,
                candidates: classification.candidates
            )
        }
    }

    private func applyWinningReferenceFilter(to regions: [LocalRegionAnalysis]) -> [LocalRegionAnalysis] {
        guard let winningRegion = regions.first(where: { $0.region == .winning }),
              let reference = bestWinningReference(from: winningRegion.detectedTiles) else {
            return regions
        }

        let referenceWidth = reference.boundingBox.width * winningRegion.imageSize.width
        let referenceHeight = reference.boundingBox.height * winningRegion.imageSize.height
        let referenceArea = referenceWidth * referenceHeight
        let widthRange = (referenceWidth * 0.70)...(referenceWidth * 1.35)
        let heightRange = (referenceHeight * 0.70)...(referenceHeight * 1.35)
        let areaRange = (referenceArea * 0.55)...(referenceArea * 1.60)

        let filteredRegions = regions.map { region in
            let filteredTiles = region.detectedTiles.filter { tile in
                let width = tile.boundingBox.width * region.imageSize.width
                let height = tile.boundingBox.height * region.imageSize.height
                let area = width * height
                return widthRange.contains(width)
                    && heightRange.contains(height)
                    && areaRange.contains(area)
            }
            return LocalRegionAnalysis(
                region: region.region,
                regionImage: region.regionImage,
                imageSize: region.imageSize,
                detectedTiles: filteredTiles
            )
        }

        let rawNonWinningCount = regions
            .filter { $0.region != .winning }
            .reduce(0) { $0 + $1.detectedTiles.count }
        let filteredNonWinningCount = filteredRegions
            .filter { $0.region != .winning }
            .reduce(0) { $0 + $1.detectedTiles.count }

        if rawNonWinningCount > 0 && filteredNonWinningCount == 0 {
            NSLog(
                "Skipping winning-reference size filter because it removed all non-winning detections (raw=%d, filtered=%d)",
                rawNonWinningCount,
                filteredNonWinningCount
            )
            return regions
        }

        return filteredRegions
    }

    private func bestWinningReference(from tiles: [LocalDetectedTile]) -> LocalDetectedTile? {
        tiles.max { lhs, rhs in
            winningReferenceScore(lhs) < winningReferenceScore(rhs)
        }
    }

    private func winningReferenceScore(_ tile: LocalDetectedTile) -> Double {
        let dx = Double(tile.boundingBox.midX - 0.5)
        let dy = Double(tile.boundingBox.midY - 0.5)
        let distancePenalty = sqrt(dx * dx + dy * dy)
        return tile.detectionConfidence - distancePenalty * 0.35
    }

    private func crop(cgImage: CGImage, boundingBox: CGRect) -> CGImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let rect = CGRect(
            x: boundingBox.minX * width,
            y: (1 - boundingBox.maxY) * height,
            width: boundingBox.width * width,
            height: boundingBox.height * height
        ).integral
        
        guard rect.width > 0, rect.height > 0 else { return nil }
        return cgImage.cropping(to: rect)
    }

    private func classifyTiles(
        from analysis: LocalImageAnalysis,
        source: PhotoRecognitionSource,
        hint: PhotoHandPatternSuggestion
    ) -> PhotoRecognitionResult? {
        let recognizedTiles = analysis.detectedTiles.compactMap(\.candidate)
        guard recognizedTiles.count >= 8 else { return nil }

        let regionResults = buildRegionResults(from: analysis)
        let tileGroups = tileGroups(from: analysis, regionResults: regionResults)
        let flattenedTiles = tileGroups.flatMap(\.tiles)
        let pattern = hint == .unknown ? inferredPattern(from: flattenedTiles) : hint
        let averageConfidence = recognizedTiles.reduce(0) { $0 + $1.confidence } / Double(recognizedTiles.count)
        let regionNotes = regionResults.map { region in
            "\(region.regionTitle)识别到 \(region.tileCount) 张牌"
        } + analysis.postProcessed.warnings
        
        return PhotoRecognitionResult(
            source: source,
            suggestedPattern: pattern,
            regionResults: regionResults,
            tileGroups: tileGroups,
            confidence: averageConfidence,
            notes: [
                "当前流程：先按 3 个区域裁图，再做单牌检测。",
                "如果胡牌区检测到牌，会用这张和牌的检测框尺寸做一轮宽松过滤，然后再做单牌分类。"
            ] + regionNotes,
            postProcessWarnings: analysis.postProcessed.warnings,
            isStructurallyValid: analysis.postProcessed.isStructurallyValid,
            croppedTileCount: analysis.detectedTiles.count,
            createdAt: .now
        )
    }

    private func buildRegionResults(from analysis: LocalImageAnalysis) -> [PhotoRecognitionRegionResult] {
        analysis.regionAnalyses.compactMap { region in
            let processedTiles: [PhotoTileToken]
            switch region.region {
            case .hand:
                processedTiles = analysis.postProcessed.hand.tiles.compactMap(\.candidate)
            case .openMelds:
                processedTiles = analysis.postProcessed.openMelds.tiles.compactMap(\.candidate)
            case .winning:
                if let winningTile = analysis.postProcessed.winning.tile,
                   let candidate = winningTile.candidate {
                    processedTiles = [candidate]
                } else {
                    processedTiles = []
                }
            }
            guard !processedTiles.isEmpty else { return nil }
            let confidence = processedTiles.reduce(0) { $0 + $1.confidence } / Double(processedTiles.count)
            return PhotoRecognitionRegionResult(
                regionKey: region.region.outputKey,
                regionTitle: region.region.title,
                tiles: processedTiles,
                confidence: confidence,
                previewImageData: jpegData(from: region.regionImage)
            )
        }
    }

    private func tileGroups(
        from analysis: LocalImageAnalysis,
        regionResults: [PhotoRecognitionRegionResult]
    ) -> [PhotoTileGroup] {
        if let regionalGroups = tileGroupsFromRegions(regionResults), !regionalGroups.isEmpty {
            return regionalGroups
        }

        if let columnGroups = columnBasedGroups(from: analysis), !columnGroups.isEmpty {
            return columnGroups
        }
        
        let groupedRows = groupedDetectedRows(from: analysis.detectedTiles)
        return tileGroupsFromRows(groupedRows)
    }

    private func columnBasedGroups(from analysis: LocalImageAnalysis) -> [PhotoTileGroup]? {
        let tiles = analysis.detectedTiles
        guard tiles.count >= 10 else { return nil }
        
        let medianWidth = median(of: tiles.map { $0.boundingBox.width })
        let clusterTolerance = max(0.03, medianWidth * 0.8)
        let xClusters = clusteredTiles(
            tiles,
            keyPath: \.boundingBox.midX,
            tolerance: clusterTolerance
        )
        guard let dominantCluster = xClusters.max(by: { $0.count < $1.count }),
              dominantCluster.count >= 10 else {
            return nil
        }
        
        let sortedMainColumn = dominantCluster.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        let yGaps = zip(sortedMainColumn, sortedMainColumn.dropFirst()).map {
            $0.0.boundingBox.minY - $0.1.boundingBox.maxY
        }
        let biggestGap = yGaps.max() ?? 0
        
        var groups: [PhotoTileGroup] = []
        if biggestGap > median(of: sortedMainColumn.map { $0.boundingBox.height }) * 0.6,
           let gapIndex = yGaps.firstIndex(of: biggestGap),
           gapIndex < sortedMainColumn.count - 1 {
            let upper = Array(sortedMainColumn.prefix(gapIndex + 1))
            let lower = Array(sortedMainColumn.suffix(from: gapIndex + 1))
            let upperTiles = upper.compactMap(\.candidate)
            let lowerTiles = lower.compactMap(\.candidate)
            
            if upperTiles.count >= 13 {
                groups.append(PhotoTileGroup(title: "手牌", tiles: Array(upperTiles.prefix(13))))
                if upperTiles.count > 13 {
                    groups.append(PhotoTileGroup(title: "和牌", tiles: [upperTiles[13]]))
                }
            } else if !upperTiles.isEmpty {
                groups.append(PhotoTileGroup(title: "手牌", tiles: upperTiles))
            }
            
            if let firstWinning = lowerTiles.first {
                groups.append(PhotoTileGroup(title: "和牌", tiles: [firstWinning]))
            }
        } else {
            let mainTiles = sortedMainColumn.compactMap(\.candidate)
            if mainTiles.count >= 14 {
                groups.append(PhotoTileGroup(title: "手牌", tiles: Array(mainTiles.prefix(13))))
                groups.append(PhotoTileGroup(title: "和牌", tiles: [mainTiles[13]]))
            } else if mainTiles.count >= 2 {
                groups.append(PhotoTileGroup(title: "手牌", tiles: Array(mainTiles.dropLast())))
                if let last = mainTiles.last {
                    groups.append(PhotoTileGroup(title: "和牌", tiles: [last]))
                }
            }
        }
        
        let sideTiles = tiles.filter { tile in
            !dominantCluster.contains(where: { $0.boundingBox == tile.boundingBox })
        }
        let sideGroups = groupedDetectedRows(from: sideTiles)
        for row in sideGroups {
            let rowTiles = row.compactMap(\.candidate)
            guard !rowTiles.isEmpty else { continue }
            groups.append(PhotoTileGroup(title: "副露\(groups.filter { $0.title.hasPrefix("副露") }.count + 1)", tiles: rowTiles))
        }
        
        return groups.isEmpty ? nil : groups
    }

    private func groupedDetectedRows(from tiles: [LocalDetectedTile]) -> [[LocalDetectedTile]] {
        let sorted = tiles.sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.07 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.midX < rhs.boundingBox.midX
        }
        
        var rows: [[LocalDetectedTile]] = []
        for tile in sorted {
            if let index = rows.firstIndex(where: { row in
                guard let reference = row.first else { return false }
                return abs(reference.boundingBox.midY - tile.boundingBox.midY) < 0.08
            }) {
                rows[index].append(tile)
            } else {
                rows.append([tile])
            }
        }
        
        return rows
            .map { row in row.sorted { $0.boundingBox.midX < $1.boundingBox.midX } }
            .sorted { lhs, rhs in
                (lhs.first?.boundingBox.midY ?? 0) > (rhs.first?.boundingBox.midY ?? 0)
            }
    }
    
    private func tileGroupsFromRows(_ rows: [[LocalDetectedTile]]) -> [PhotoTileGroup] {
        guard let mainRowIndex = rows.enumerated().max(by: { $0.element.count < $1.element.count })?.offset else {
            return []
        }
        
        var groups: [PhotoTileGroup] = []
        
        for (index, row) in rows.enumerated() {
            let rowTiles = row.compactMap(\.candidate)
            guard !rowTiles.isEmpty else { continue }
            
            if index == mainRowIndex {
                if rowTiles.count >= 14 {
                    groups.append(PhotoTileGroup(title: "手牌", tiles: Array(rowTiles.prefix(13))))
                    groups.append(PhotoTileGroup(title: "和牌", tiles: [rowTiles[13]]))
                } else if rowTiles.count == 13 {
                    groups.append(PhotoTileGroup(title: "手牌", tiles: Array(rowTiles.prefix(12))))
                    groups.append(PhotoTileGroup(title: "和牌", tiles: [rowTiles[12]]))
                } else {
                    groups.append(PhotoTileGroup(title: "手牌", tiles: rowTiles))
                }
            } else {
                groups.append(PhotoTileGroup(title: "副露\(groups.filter { $0.title.hasPrefix("副露") }.count + 1)", tiles: rowTiles))
            }
        }
        
        if !groups.contains(where: { $0.title == "和牌" }),
           let handIndex = groups.firstIndex(where: { $0.title == "手牌" }),
           groups[handIndex].tiles.count >= 2 {
            let winningTile = groups[handIndex].tiles.removeLast()
            groups.append(PhotoTileGroup(title: "和牌", tiles: [winningTile]))
        }
        
        return groups
    }

    private func tileGroupsFromRegions(_ regions: [PhotoRecognitionRegionResult]) -> [PhotoTileGroup]? {
        guard !regions.isEmpty else { return nil }

        var groups: [PhotoTileGroup] = []
        let handTiles = regions
            .first(where: { $0.regionKey == PhotoCaptureRegion.hand.outputKey })?
            .tiles ?? []
        let openTiles = regions
            .first(where: { $0.regionKey == PhotoCaptureRegion.openMelds.outputKey })?
            .tiles ?? []
        let winningTiles = regions
            .first(where: { $0.regionKey == PhotoCaptureRegion.winning.outputKey })?
            .tiles ?? []

        if !handTiles.isEmpty {
            groups.append(PhotoTileGroup(title: "手牌", tiles: handTiles))
        }
        if !openTiles.isEmpty {
            groups.append(PhotoTileGroup(title: "副露1", tiles: openTiles))
        }
        if let winningTile = winningTiles.first {
            groups.append(PhotoTileGroup(title: "和牌", tiles: [winningTile]))
        }

        return groups.isEmpty ? nil : groups
    }

    private func buildPostProcessedAnalysis(from regions: [LocalRegionAnalysis]) -> PhotoRecognitionPostProcessResult {
        let mapped = Dictionary(uniqueKeysWithValues: regions.map { region in
            (
                region.region,
                region.detectedTiles.map {
                    PostProcessDetectedTile(
                        boundingBox: $0.boundingBox,
                        candidate: $0.candidate,
                        candidates: $0.candidates
                    )
                }
            )
        })
        return postProcessor.process(regions: mapped)
    }

    private func clusteredTiles(
        _ tiles: [LocalDetectedTile],
        keyPath: KeyPath<LocalDetectedTile, CGFloat>,
        tolerance: CGFloat
    ) -> [[LocalDetectedTile]] {
        let sorted = tiles.sorted { $0[keyPath: keyPath] < $1[keyPath: keyPath] }
        var clusters: [[LocalDetectedTile]] = []
        
        for tile in sorted {
            if let lastIndex = clusters.indices.last,
               let lastValue = clusters[lastIndex].last?[keyPath: keyPath],
               abs(lastValue - tile[keyPath: keyPath]) <= tolerance {
                clusters[lastIndex].append(tile)
            } else {
                clusters.append([tile])
            }
        }
        
        return clusters
    }

    private func median(of values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
    
    private func inferredPattern(from tiles: [PhotoTileToken]) -> PhotoHandPatternSuggestion {
        let names = tiles.map(\.displayName)
        let counts = Dictionary(grouping: names, by: { $0 }).mapValues(\.count)
        
        if Set(names).isSuperset(of: ["1万", "9万", "1筒", "9筒", "1索", "9索", "东", "南", "西", "北", "白", "发", "中"]) {
            return .kokushi
        }
        if counts.values.filter({ $0 == 2 }).count >= 6 {
            return .sevenPairs
        }
        if counts.values.filter({ $0 >= 3 }).count >= 3 {
            return .triplet
        }
        return .standard
    }
    
    private func failedRecognitionResult(
        from analysis: LocalImageAnalysis,
        source: PhotoRecognitionSource
    ) -> PhotoRecognitionResult {
        let regionResults = buildRegionResults(from: analysis)
        let segmentedCount = analysis.regionAnalyses.count
        let detectedCount = analysis.detectedTiles.count
        let classifiedCount = analysis.detectedTiles.compactMap(\.candidate).count
        let notes = [
            "阶段 1 裁剪：已按手牌区 / 副露区 / 胡牌区切成 \(segmentedCount) 个区域。",
            "阶段 2 检测：共找到约 \(detectedCount) 个候选牌块。",
            "阶段 3 分类：仅有 \(classifiedCount) 张牌得到可用结果，暂时不足以稳定组牌。",
            "当前不会再自动回退到 mock 结果，请先根据三块裁剪图检查是裁剪问题还是单牌识别问题。"
        ] + analysis.postProcessed.warnings

        return PhotoRecognitionResult(
            source: source,
            suggestedPattern: .unknown,
            regionResults: regionResults,
            tileGroups: [],
            confidence: classifiedCount == 0 ? 0 : Double(classifiedCount) / Double(max(detectedCount, 1)),
            notes: notes,
            postProcessWarnings: analysis.postProcessed.warnings,
            isStructurallyValid: analysis.postProcessed.isStructurallyValid,
            croppedTileCount: detectedCount,
            createdAt: .now
        )
    }

    private func jpegData(from cgImage: CGImage) -> Data? {
        UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
    }

}

private struct LocalImageAnalysis {
    var imageSize: CGSize
    var detectedTiles: [LocalDetectedTile]
    var regionAnalyses: [LocalRegionAnalysis]
    var postProcessed: PhotoRecognitionPostProcessResult
}

private struct LocalDetectedTile {
    var boundingBox: CGRect
    var detectionConfidence: Double = 1.0
    var candidate: PhotoTileToken?
    var candidates: [PhotoTileToken] = []
}

private struct LocalRegionAnalysis {
    var region: PhotoCaptureRegion
    var regionImage: CGImage
    var imageSize: CGSize
    var detectedTiles: [LocalDetectedTile]
}
