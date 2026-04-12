import Foundation
import Vision
import CoreML
import CoreGraphics
import UIKit

struct PhotoTileClassification {
    var bestMatch: PhotoTileToken?
    var candidates: [PhotoTileToken]
}

protocol SingleTileClassifier: Sendable {
    func classifyTile(in cgImage: CGImage) -> PhotoTileClassification
}

struct CoreMLSingleTileClassifier: SingleTileClassifier {
    private let retryThreshold = 0.9

    func classifyTile(in cgImage: CGImage) -> PhotoTileClassification {
        let matcher = CoreMLSingleTileMatcher()
        var rankedCandidates = matcher.match(cgImage: cgImage)

        if (rankedCandidates.first?.confidence ?? 0) < retryThreshold {
            for variant in TileClassificationRetryVariants.makeRetryImages(from: cgImage) {
                let variantCandidates = matcher.match(cgImage: variant)
                guard let variantBest = variantCandidates.first else { continue }
                let currentBestConfidence = rankedCandidates.first?.confidence ?? 0
                if variantBest.confidence > currentBestConfidence {
                    rankedCandidates = variantCandidates
                }
            }
        }

        return PhotoTileClassification(
            bestMatch: rankedCandidates.first,
            candidates: Array(rankedCandidates.prefix(3))
        )
    }
}

private enum TileClassificationRetryVariants {
    static func makeRetryImages(from cgImage: CGImage) -> [CGImage] {
        var images: [CGImage?] = [
            rotate180(cgImage),
            insetCrop(cgImage, fraction: 0.04),
            insetCrop(cgImage, fraction: 0.08),
            padded(cgImage, fraction: 0.06)
        ]
        if let rotated = rotate180(cgImage) {
            images.append(padded(rotated, fraction: 0.06))
        }
        return images.compactMap { $0 }
    }

    private static func rotate180(_ cgImage: CGImage) -> CGImage? {
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let cgContext = context.cgContext
            cgContext.translateBy(x: size.width, y: size.height)
            cgContext.rotate(by: .pi)
            cgContext.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
        return image.cgImage
    }

    private static func insetCrop(_ cgImage: CGImage, fraction: CGFloat) -> CGImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let insetX = max(1, width * fraction)
        let insetY = max(1, height * fraction)
        let rect = CGRect(
            x: insetX,
            y: insetY,
            width: width - insetX * 2,
            height: height - insetY * 2
        ).integral
        guard rect.width > 8, rect.height > 8 else { return nil }
        return cgImage.cropping(to: rect)
    }

    private static func padded(_ cgImage: CGImage, fraction: CGFloat) -> CGImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let padX = width * fraction
        let padY = height * fraction
        let canvasSize = CGSize(width: width + padX * 2, height: height + padY * 2)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))
            UIImage(cgImage: cgImage).draw(in: CGRect(x: padX, y: padY, width: width, height: height))
        }
        return image.cgImage
    }
}

struct VisionOCRSingleTileClassifier: SingleTileClassifier {
    func classifyTile(in cgImage: CGImage) -> PhotoTileClassification {
        var rankedCandidates = CoreMLSingleTileMatcher().match(cgImage: cgImage)
        let ocrCandidates = rankCandidates(from: recognizeStrings(in: cgImage))
        let templateCandidates = GlyphTemplateTileMatcher().match(cgImage: cgImage)
        
        for candidate in ocrCandidates + templateCandidates {
            if let existingIndex = rankedCandidates.firstIndex(where: { $0.displayName == candidate.displayName }) {
                rankedCandidates[existingIndex].confidence = max(
                    rankedCandidates[existingIndex].confidence,
                    candidate.confidence
                )
            } else {
                rankedCandidates.append(candidate)
            }
        }
        
        rankedCandidates.sort { lhs, rhs in
            lhs.confidence > rhs.confidence
        }
        
        if rankedCandidates.isEmpty {
            let templateOnly = templateCandidates.sorted { lhs, rhs in
                lhs.confidence > rhs.confidence
            }
            return PhotoTileClassification(
                bestMatch: templateOnly.first,
                candidates: Array(templateOnly.prefix(3))
            )
        }
        
        return PhotoTileClassification(
            bestMatch: rankedCandidates.first,
            candidates: Array(rankedCandidates.prefix(3))
        )
    }
    
    private func recognizeStrings(in cgImage: CGImage) -> [(String, Float)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.08
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        
        return (request.results ?? [])
            .flatMap { observation in
                observation.topCandidates(5).map { ($0.string, $0.confidence) }
            }
    }
    
    private func rankCandidates(from recognizedStrings: [(String, Float)]) -> [PhotoTileToken] {
        var ranked: [PhotoTileToken] = []
        var seenNames = Set<String>()
        
        for (rawText, baseConfidence) in recognizedStrings {
            for token in parseTokens(from: rawText, baseConfidence: baseConfidence) {
                let name = token.displayName
                guard !name.isEmpty, !seenNames.contains(name) else { continue }
                ranked.append(token)
                seenNames.insert(name)
            }
        }
        
        return ranked.sorted { lhs, rhs in
            lhs.confidence > rhs.confidence
        }
    }
    
    private func parseTokens(from rawText: String, baseConfidence: Float) -> [PhotoTileToken] {
        let normalized = normalize(rawText)
        guard !normalized.isEmpty else { return [] }
        
        var matches: [PhotoTileToken] = []
        
        for honor in honorMappings {
            if normalized.contains(honor.key) {
                matches.append(.honor(honor.value, confidence: adjustedConfidence(base: baseConfidence, bonus: 0.16)))
            }
        }
        
        let rankCandidates = extractRankCandidates(from: normalized)
        for rank in rankCandidates {
            for suit in suitMappings {
                if normalized.contains(suit.key) {
                    matches.append(
                        .suited(
                            suit.value,
                            rank: rank,
                            confidence: adjustedConfidence(base: baseConfidence, bonus: 0.12)
                        )
                    )
                }
            }
        }
        
        if matches.isEmpty, let rank = rankCandidates.first {
            matches.append(.suited(.man, rank: rank, confidence: adjustedConfidence(base: baseConfidence, bonus: -0.12)))
            matches.append(.suited(.pin, rank: rank, confidence: adjustedConfidence(base: baseConfidence, bonus: -0.12)))
            matches.append(.suited(.sou, rank: rank, confidence: adjustedConfidence(base: baseConfidence, bonus: -0.12)))
        }
        
        return matches
    }
    
    private func normalize(_ rawText: String) -> String {
        rawText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "l", with: "1")
            .replacingOccurrences(of: "i", with: "1")
            .replacingOccurrences(of: "o", with: "0")
            .replacingOccurrences(of: "bamboo", with: "sou")
            .replacingOccurrences(of: "bam", with: "sou")
            .replacingOccurrences(of: "circle", with: "pin")
            .lowercased()
    }
    
    private func extractRankCandidates(from normalized: String) -> [Int] {
        let digits = normalized.compactMap { character -> Int? in
            guard character.isNumber else { return nil }
            return Int(String(character))
        }
        return digits.filter { (1...9).contains($0) }
    }
    
    private func adjustedConfidence(base: Float, bonus: Double) -> Double {
        max(0.1, min(0.98, Double(base) + bonus))
    }
    
    private var suitMappings: [(key: String, value: PhotoTileSuit)] {
        [
            ("万", .man), ("man", .man), ("wan", .man),
            ("筒", .pin), ("pin", .pin), ("tong", .pin),
            ("索", .sou), ("sou", .sou), ("suo", .sou)
        ]
    }
    
    private var honorMappings: [(key: String, value: String)] {
        [
            ("east", "东"), ("东", "东"),
            ("south", "南"), ("南", "南"),
            ("west", "西"), ("西", "西"),
            ("north", "北"), ("北", "北"),
            ("白", "白"),
            ("发", "发"),
            ("中", "中")
        ]
    }
}

private struct CoreMLSingleTileMatcher {
    private enum GroupKey: String {
        case man
        case pin
        case sou
        case honor
    }

    private struct ModelSpec {
        let packageName: String
        let classNames: [String]

        static let full = ModelSpec(
            packageName: "MahjongTileClassifier34.mlpackage",
            classNames: [
                "east", "green",
                "man1", "man2", "man3", "man4", "man5", "man6", "man7", "man8", "man9",
                "north",
                "pin1", "pin2", "pin3", "pin4", "pin5", "pin6", "pin7", "pin8", "pin9",
                "red",
                "sou1", "sou2", "sou3", "sou4", "sou5", "sou6", "sou7", "sou8", "sou9",
                "south", "west", "white"
            ]
        )

        static let man = ModelSpec(
            packageName: "MahjongTileClassifierMan.mlpackage",
            classNames: ["man1", "man2", "man3", "man4", "man5", "man6", "man7", "man8", "man9"]
        )

        static let pin = ModelSpec(
            packageName: "MahjongTileClassifierPin.mlpackage",
            classNames: ["pin1", "pin2", "pin3", "pin4", "pin5", "pin6", "pin7", "pin8", "pin9"]
        )

        static let sou = ModelSpec(
            packageName: "MahjongTileClassifierSou.mlpackage",
            classNames: ["sou1", "sou2", "sou3", "sou4", "sou5", "sou6", "sou7", "sou8", "sou9"]
        )

        static let honor = ModelSpec(
            packageName: "MahjongTileClassifierHonor.mlpackage",
            classNames: ["east", "green", "north", "red", "south", "west", "white"]
        )

        static let legacy = ModelSpec(
            packageName: "MahjongTileClassifier.mlpackage",
            classNames: [
                "man1", "man2", "man3", "man4", "man5", "man6", "man7", "man8", "man9",
                "pin1", "pin2", "pin3", "pin4", "pin5", "pin6", "pin7", "pin8", "pin9",
                "sou1", "sou2", "sou3", "sou4", "sou5", "sou6", "sou7", "sou8", "sou9",
                "east", "south", "west", "north", "white", "green", "red"
            ]
        )

        static func subgroup(for key: GroupKey) -> ModelSpec {
            switch key {
            case .man: return .man
            case .pin: return .pin
            case .sou: return .sou
            case .honor: return .honor
            }
        }
    }
    
    func match(cgImage: CGImage) -> [PhotoTileToken] {
        if let ranked = hierarchicalMatch(cgImage: cgImage), !ranked.isEmpty {
            return ranked
        }
        return legacyMatch(cgImage: cgImage)
    }

    private func hierarchicalMatch(cgImage: CGImage) -> [PhotoTileToken]? {
        guard let fullProbabilities = inferProbabilities(in: cgImage, spec: .full) else {
            return nil
        }

        let fullByClass = Dictionary(uniqueKeysWithValues: zip(ModelSpec.full.classNames, fullProbabilities))
        let bestGroup = bestGroup(from: fullByClass)
        let subgroupSpec = ModelSpec.subgroup(for: bestGroup.key)
        logGroupSummary(fullByClass, bestGroup: bestGroup)

        guard let subgroupProbabilities = inferProbabilities(in: cgImage, spec: subgroupSpec) else {
            return topTokens(
                from: fullProbabilities,
                classNames: ModelSpec.full.classNames,
                limit: 3
            )
        }

        let ranked = zip(subgroupSpec.classNames, subgroupProbabilities)
            .map { className, subgroupProbability in
                let fullProbability = fullByClass[className] ?? 0
                let combinedConfidence = max(fullProbability, bestGroup.probability * subgroupProbability)
                return (className, combinedConfidence)
            }
            .sorted { lhs, rhs in
                lhs.1 > rhs.1
            }
            .prefix(3)

        #if DEBUG
        let summary = ranked
            .map { "\($0.0)=\(String(format: "%.4f", $0.1))" }
            .joined(separator: ", ")
        NSLog("[TileClassifier] hierarchical final top3: %@", summary)
        #endif

        return ranked.compactMap { token(for: $0.0, confidence: $0.1) }
    }

    private func legacyMatch(cgImage: CGImage) -> [PhotoTileToken] {
        guard let probabilities = inferProbabilities(in: cgImage, spec: .legacy) else {
            return []
        }
        return topTokens(
            from: probabilities,
            classNames: ModelSpec.legacy.classNames,
            limit: 3
        )
    }
    
    private func token(for className: String, confidence: Double) -> PhotoTileToken? {
        if className.hasPrefix("man"), let rank = Int(className.dropFirst(3)) {
            return .suited(.man, rank: rank, confidence: confidence)
        }
        if className.hasPrefix("pin"), let rank = Int(className.dropFirst(3)) {
            return .suited(.pin, rank: rank, confidence: confidence)
        }
        if className.hasPrefix("sou"), let rank = Int(className.dropFirst(3)) {
            return .suited(.sou, rank: rank, confidence: confidence)
        }
        
        let honors: [String: String] = [
            "east": "东",
            "south": "南",
            "west": "西",
            "north": "北",
            "white": "白",
            "green": "发",
            "red": "中"
        ]
        if let name = honors[className] {
            return .honor(name, confidence: confidence)
        }
        return nil
    }

    private func bestGroup(from probabilities: [String: Double]) -> (key: GroupKey, probability: Double) {
        let groups: [(GroupKey, [String])] = [
            (.man, ModelSpec.man.classNames),
            (.pin, ModelSpec.pin.classNames),
            (.sou, ModelSpec.sou.classNames),
            (.honor, ModelSpec.honor.classNames)
        ]

        return groups
            .map { key, classNames in
                let score = classNames.reduce(0.0) { partial, className in
                    partial + (probabilities[className] ?? 0)
                }
                return (key, score)
            }
            .max { lhs, rhs in lhs.1 < rhs.1 } ?? (.man, 0)
    }

    private func topTokens(from probabilities: [Double], classNames: [String], limit: Int) -> [PhotoTileToken] {
        probabilities.enumerated()
            .sorted { lhs, rhs in lhs.element > rhs.element }
            .prefix(limit)
            .compactMap { pair in
                guard pair.offset < classNames.count else { return nil }
                return token(for: classNames[pair.offset], confidence: pair.element)
            }
    }

    private func inferProbabilities(in cgImage: CGImage, spec: ModelSpec) -> [Double]? {
        if let directProbabilities = inferProbabilitiesDirect(in: cgImage, spec: spec) {
            return directProbabilities
        }

        guard let visionModel = Self.loadVisionModel(named: spec.packageName) else {
            return nil
        }

        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        if let observation = request.results?.first as? VNCoreMLFeatureValueObservation,
           let multiArray = observation.featureValue.multiArrayValue {
            let logits = (0..<multiArray.count).map { index in
                multiArray[index].doubleValue
            }
            let probabilities = softmax(logits)
            logTopClasses(source: "vision-multiarray", spec: spec, probabilities: probabilities)
            return probabilities
        }

        if let classifications = request.results as? [VNClassificationObservation], !classifications.isEmpty {
            let confidences = Dictionary(uniqueKeysWithValues: classifications.map { ($0.identifier, Double($0.confidence)) })
            let probabilities = spec.classNames.map { confidences[$0] ?? 0 }
            #if DEBUG
            let identifiers = classifications
                .prefix(5)
                .map { "\($0.identifier)=\(String(format: "%.4f", $0.confidence))" }
                .joined(separator: ", ")
            NSLog("[TileClassifier] vision-classifications %@ => %@", spec.packageName, identifiers)
            #endif
            logTopClasses(source: "vision-classification", spec: spec, probabilities: probabilities)
            return probabilities
        }

        NSLog("Vision classifier produced no usable result for %@", spec.packageName)
        return nil
    }

    private func inferProbabilitiesDirect(in cgImage: CGImage, spec: ModelSpec) -> [Double]? {
        guard let model = Self.loadModel(named: spec.packageName) else {
            return nil
        }

        let inputName = model.modelDescription.inputDescriptionsByName.keys.first ?? "image"
        let outputName = model.modelDescription.outputDescriptionsByName.keys.first ?? "var_740"

        guard
            let pixelBuffer = try? MLFeatureValue(
                cgImage: cgImage,
                pixelsWide: 224,
                pixelsHigh: 224,
                pixelFormatType: kCVPixelFormatType_32ARGB,
                options: nil
            ).imageBufferValue,
            let input = try? MLDictionaryFeatureProvider(dictionary: [
                inputName: MLFeatureValue(pixelBuffer: pixelBuffer)
            ]),
            let output = try? model.prediction(from: input),
            let multiArray = output.featureValue(for: outputName)?.multiArrayValue
        else {
            NSLog("Direct CoreML classifier inference failed for %@", spec.packageName)
            return nil
        }

        let logits = (0..<multiArray.count).map { index in
            multiArray[index].doubleValue
        }

        logRawLogits(spec: spec, logits: logits, model: model)

        guard logits.count == spec.classNames.count else {
            NSLog(
                "Classifier output size mismatch for %@: got %ld expected %ld",
                spec.packageName,
                logits.count,
                spec.classNames.count
            )
            return nil
        }

        let probabilities = softmax(logits)
        logTopClasses(source: "direct", spec: spec, probabilities: probabilities)
        return probabilities
    }

    private func logRawLogits(spec: ModelSpec, logits: [Double], model: MLModel) {
        #if DEBUG
        let nanCount = logits.filter { $0.isNaN }.count
        let infCount = logits.filter { $0.isInfinite }.count
        let finite = logits.filter { $0.isFinite }
        let minValue = finite.min() ?? .nan
        let maxValue = finite.max() ?? .nan
        let firstValues = logits
            .prefix(5)
            .map { String(format: "%.6f", $0) }
            .joined(separator: ", ")
        NSLog(
            "[TileClassifier] raw %@ path=%@ count=%ld nan=%ld inf=%ld min=%.6f max=%.6f first=[%@]",
            spec.packageName,
            model.modelDescription.metadata[.author] as? String ?? "n/a",
            logits.count,
            nanCount,
            infCount,
            minValue,
            maxValue,
            firstValues
        )
        #endif
    }

    private func logGroupSummary(
        _ fullByClass: [String: Double],
        bestGroup: (key: GroupKey, probability: Double)
    ) {
        #if DEBUG
        let groupScores: [(String, Double)] = [
            ("man", ModelSpec.man.classNames.reduce(0) { $0 + (fullByClass[$1] ?? 0) }),
            ("pin", ModelSpec.pin.classNames.reduce(0) { $0 + (fullByClass[$1] ?? 0) }),
            ("sou", ModelSpec.sou.classNames.reduce(0) { $0 + (fullByClass[$1] ?? 0) }),
            ("honor", ModelSpec.honor.classNames.reduce(0) { $0 + (fullByClass[$1] ?? 0) })
        ]
        let summary = groupScores
            .map { "\($0.0)=\(String(format: "%.4f", $0.1))" }
            .joined(separator: ", ")
        NSLog(
            "[TileClassifier] full-group best=%@ prob=%.4f all={%@}",
            String(describing: bestGroup.key),
            bestGroup.probability,
            summary
        )
        #endif
    }

    private func logTopClasses(source: String, spec: ModelSpec, probabilities: [Double]) {
        #if DEBUG
        let top = zip(spec.classNames, probabilities)
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { "\($0.0)=\(String(format: "%.4f", $0.1))" }
            .joined(separator: ", ")
        NSLog("[TileClassifier] %@ %@ top3: %@", source, spec.packageName, top)
        #endif
    }
    
    private func softmax(_ logits: [Double]) -> [Double] {
        guard let maxLogit = logits.max() else { return [] }
        let exps = logits.map { Foundation.exp($0 - maxLogit) }
        let sum = exps.reduce(0, +)
        guard sum > 0 else { return Array(repeating: 0, count: logits.count) }
        return exps.map { $0 / sum }
    }
    
    private static func loadVisionModel(named packageName: String) -> VNCoreMLModel? {
        if let cached = ModelCache.shared.visionModels[packageName] {
            return cached
        }

        guard let model = loadModel(named: packageName),
              let visionModel = try? VNCoreMLModel(for: model) else {
            return nil
        }

        ModelCache.shared.visionModels[packageName] = visionModel
        return visionModel
    }

    private static func loadModel(named packageName: String) -> MLModel? {
        if let cached = ModelCache.shared.mlModels[packageName] {
            return cached
        }

        let bundle = Bundle.main
        let compiledName = ((packageName as NSString).deletingPathExtension as NSString)
            .appendingPathExtension("mlmodelc") ?? packageName

        let compiledCandidates =
            (bundle.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil) ?? []) +
            (bundle.urls(forResourcesWithExtension: "mlmodelc", subdirectory: "PhotoRecognition") ?? [])
        if let compiledURL = compiledCandidates.first(where: { $0.lastPathComponent == compiledName }),
           let model = try? MLModel(contentsOf: compiledURL) {
            #if DEBUG
            NSLog("Loaded CoreML classifier compiled model %@ from %@", packageName, compiledURL.path)
            #endif
            ModelCache.shared.mlModels[packageName] = model
            return model
        }

        let packageCandidates =
            (bundle.urls(forResourcesWithExtension: "mlpackage", subdirectory: nil) ?? []) +
            (bundle.urls(forResourcesWithExtension: "mlpackage", subdirectory: "PhotoRecognition") ?? [])
        guard let packageURL = packageCandidates.first(where: { $0.lastPathComponent == packageName }) else {
            NSLog("CoreML classifier package not found in bundle: %@", packageName)
            return nil
        }

        guard
            let compiledURL = try? MLModel.compileModel(at: packageURL),
            let model = try? MLModel(contentsOf: compiledURL)
        else {
            NSLog("Failed to compile/load CoreML classifier package: %@", packageName)
            return nil
        }

        #if DEBUG
        NSLog("Compiled CoreML classifier package %@ to %@", packageName, compiledURL.path)
        #endif
        ModelCache.shared.mlModels[packageName] = model
        return model
    }
    
    private final class ModelCache: @unchecked Sendable {
        static let shared = ModelCache()
        var visionModels: [String: VNCoreMLModel] = [:]
        var mlModels: [String: MLModel] = [:]
    }
}

private struct GlyphTemplateTileMatcher {
    private let candidateTiles: [PhotoTileToken] = {
        var tiles: [PhotoTileToken] = []
        for rank in 1...9 {
            tiles.append(.suited(.man, rank: rank, confidence: 0.4))
            tiles.append(.suited(.pin, rank: rank, confidence: 0.4))
            tiles.append(.suited(.sou, rank: rank, confidence: 0.4))
        }
        tiles.append(contentsOf: [
            .honor("东", confidence: 0.4),
            .honor("南", confidence: 0.4),
            .honor("西", confidence: 0.4),
            .honor("北", confidence: 0.4),
            .honor("白", confidence: 0.4),
            .honor("发", confidence: 0.4),
            .honor("中", confidence: 0.4)
        ])
        return tiles
    }()
    
    func match(cgImage: CGImage) -> [PhotoTileToken] {
        guard let normalizedInput = normalizedPixelVector(from: cgImage) else {
            return []
        }
        
        let ranked = candidateTiles.compactMap { token -> PhotoTileToken? in
            guard let templateImage = renderedTemplate(for: token.displayName),
                  let normalizedTemplate = normalizedPixelVector(from: templateImage) else {
                return nil
            }
            
            let score = similarity(lhs: normalizedInput, rhs: normalizedTemplate)
            guard score > 0.58 else { return nil }
            
            var updated = token
            updated.confidence = max(token.confidence, score)
            return updated
        }
        .sorted { lhs, rhs in
            lhs.confidence > rhs.confidence
        }
        
        return Array(ranked.prefix(3))
    }
    
    private func renderedTemplate(for text: String) -> CGImage? {
        let size = CGSize(width: 88, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 30),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ]
            
            let rect = CGRect(x: 8, y: 32, width: size.width - 16, height: 50)
            (text as NSString).draw(in: rect, withAttributes: attributes)
        }
        return image.cgImage
    }
    
    private func normalizedPixelVector(from cgImage: CGImage) -> [UInt8]? {
        let width = 24
        let height = 32
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)
        
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
    
    private func similarity(lhs: [UInt8], rhs: [UInt8]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        let difference = zip(lhs, rhs).reduce(0.0) { partial, pair in
            partial + abs(Double(pair.0) - Double(pair.1))
        }
        let maxDifference = Double(lhs.count) * 255.0
        return max(0, 1 - difference / maxDifference)
    }
}
