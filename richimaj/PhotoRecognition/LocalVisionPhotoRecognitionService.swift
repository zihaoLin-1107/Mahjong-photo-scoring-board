import Foundation
import Vision
import CoreGraphics
import ImageIO

struct LocalVisionPhotoRecognitionService: PhotoRecognitionService {
    private let fallbackService: MockPhotoRecognitionService
    private let tileClassifier: any SingleTileClassifier
    
    init(
        fallbackService: MockPhotoRecognitionService = MockPhotoRecognitionService(),
        tileClassifier: any SingleTileClassifier = VisionOCRSingleTileClassifier()
    ) {
        self.fallbackService = fallbackService
        self.tileClassifier = tileClassifier
    }
    
    func recognize(request: PhotoRecognitionRequest) async throws -> PhotoRecognitionResult {
        switch request.source {
        case .sample:
            return try await fallbackService.recognize(request: request)
        case .camera, .photoLibrary:
            guard let imageData = request.imageData else {
                throw PhotoRecognitionServiceError.unsupportedInput
            }
            
            let analysis = try analyzeImageData(imageData)
            if let classifiedResult = classifyTiles(from: analysis, source: request.source, hint: request.handPatternHint) {
                return classifiedResult
            }
            
            let fallback = try await fallbackService.recognize(request: request)
            return mergedFallbackResult(from: analysis, fallback: fallback, source: request.source)
        }
    }
    
    private func analyzeImageData(_ imageData: Data) throws -> LocalImageAnalysis {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw PhotoRecognitionServiceError.unsupportedInput
        }
        
        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.minimumAspectRatio = 0.2
        rectangleRequest.maximumAspectRatio = 0.9
        rectangleRequest.minimumSize = 0.02
        rectangleRequest.maximumObservations = 30
        
        let imageHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try imageHandler.perform([rectangleRequest])
        
        let rectangles = (rectangleRequest.results ?? [])
            .map { observation in
                LocalDetectedTile(
                    boundingBox: observation.boundingBox,
                    candidate: nil
                )
            }
            .sorted { lhs, rhs in
                let yDifference = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                if yDifference > 0.08 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.midX < rhs.boundingBox.midX
            }
        
        let classifiedTiles = rectangles.compactMap { tile -> LocalDetectedTile? in
            guard let croppedImage = crop(cgImage: cgImage, boundingBox: tile.boundingBox) else {
                return tile
            }
            
            let classification = tileClassifier.classifyTile(in: croppedImage)
            return LocalDetectedTile(
                boundingBox: tile.boundingBox,
                candidate: classification.bestMatch,
                candidates: classification.candidates
            )
        }
        
        return LocalImageAnalysis(detectedTiles: classifiedTiles)
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

        let groupedRows = groupedDetectedRows(from: analysis.detectedTiles)
        let tileGroups = tileGroupsFromRows(groupedRows)
        let flattenedTiles = tileGroups.flatMap(\.tiles)
        let pattern = hint == .unknown ? inferredPattern(from: flattenedTiles) : hint
        let averageConfidence = recognizedTiles.reduce(0) { $0 + $1.confidence } / Double(recognizedTiles.count)
        
        return PhotoRecognitionResult(
            source: source,
            suggestedPattern: pattern,
            tileGroups: tileGroups,
            confidence: averageConfidence,
            notes: [
                "当前使用本地 Vision 做整体牌列检测，再按布局拆成手牌、胡牌和副露区域。",
                "底层仍然会对每张候选牌做分类，但对外展示的是整手结构结果。",
                "单张牌分类器现在带了 OCR + 模板匹配双兜底，先尽量减少万、筒、索混淆。"
            ],
            croppedTileCount: analysis.detectedTiles.count
        )
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
    
    private func mergedFallbackResult(
        from analysis: LocalImageAnalysis,
        fallback: PhotoRecognitionResult,
        source: PhotoRecognitionSource
    ) -> PhotoRecognitionResult {
        var notes = fallback.notes
        notes.insert("当前走的是本地 Vision 识别路径，但这张图还没稳定裁切出足够多的牌面。", at: 0)
        notes.append("本地预分析检测到约 \(analysis.detectedTiles.count) 个候选牌面区域。")
        
        return PhotoRecognitionResult(
            source: source,
            suggestedPattern: fallback.suggestedPattern,
            tileGroups: fallback.tileGroups,
            confidence: min(0.82, fallback.confidence),
            notes: notes,
            croppedTileCount: analysis.detectedTiles.count
        )
    }
}

private struct LocalImageAnalysis {
    var detectedTiles: [LocalDetectedTile]
}

private struct LocalDetectedTile {
    var boundingBox: CGRect
    var candidate: PhotoTileToken?
    var candidates: [PhotoTileToken] = []
}
