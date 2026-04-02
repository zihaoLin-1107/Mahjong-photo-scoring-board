import Foundation
import Vision
import CoreGraphics
import UIKit

struct PhotoTileClassification {
    var bestMatch: PhotoTileToken?
    var candidates: [PhotoTileToken]
}

protocol SingleTileClassifier {
    func classifyTile(in cgImage: CGImage) -> PhotoTileClassification
}

struct VisionOCRSingleTileClassifier: SingleTileClassifier {
    func classifyTile(in cgImage: CGImage) -> PhotoTileClassification {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.08
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        
        let recognizedStrings = (request.results ?? [])
            .flatMap { observation in
                observation.topCandidates(5).map { ($0.string, $0.confidence) }
            }
        
        var rankedCandidates = rankCandidates(from: recognizedStrings)
        let templateCandidates = GlyphTemplateTileMatcher().match(cgImage: cgImage)
        
        for templateCandidate in templateCandidates {
            if let existingIndex = rankedCandidates.firstIndex(where: { $0.displayName == templateCandidate.displayName }) {
                rankedCandidates[existingIndex].confidence = max(
                    rankedCandidates[existingIndex].confidence,
                    templateCandidate.confidence
                )
            } else {
                rankedCandidates.append(templateCandidate)
            }
        }
        
        rankedCandidates.sort { lhs, rhs in
            lhs.confidence > rhs.confidence
        }
        return PhotoTileClassification(
            bestMatch: rankedCandidates.first,
            candidates: Array(rankedCandidates.prefix(3))
        )
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
