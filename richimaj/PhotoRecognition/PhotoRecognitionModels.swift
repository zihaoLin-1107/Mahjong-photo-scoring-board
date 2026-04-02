import Foundation

enum PhotoRecognitionSource: String, CaseIterable, Identifiable {
    case camera = "拍照"
    case photoLibrary = "相册"
    case sample = "示例"
    
    var id: String { rawValue }
}

enum PhotoHandPatternSuggestion: String, CaseIterable, Identifiable {
    case unknown = "未确定"
    case standard = "标准手"
    case sevenPairs = "七对子"
    case kokushi = "国士无双"
    case triplet = "对对和"
    
    var id: String { rawValue }
}

enum PhotoTileSuit: String, CaseIterable, Identifiable {
    case man = "万"
    case pin = "筒"
    case sou = "索"
    case honor = "字"
    
    var id: String { rawValue }
}

struct PhotoTileToken: Identifiable, Hashable {
    let id = UUID()
    var suit: PhotoTileSuit
    var rank: Int?
    var honorName: String?
    var confidence: Double = 1.0
    
    var displayName: String {
        switch suit {
        case .man, .pin, .sou:
            guard let rank else { return "" }
            return "\(rank)\(suit.rawValue)"
        case .honor:
            return honorName ?? ""
        }
    }
    
    var subtitle: String {
        String(format: "%.0f%%", max(0, min(1, confidence)) * 100)
    }
    
    static func suited(_ suit: PhotoTileSuit, rank: Int, confidence: Double = 1.0) -> PhotoTileToken {
        PhotoTileToken(suit: suit, rank: rank, honorName: nil, confidence: confidence)
    }
    
    static func honor(_ name: String, confidence: Double = 1.0) -> PhotoTileToken {
        PhotoTileToken(suit: .honor, rank: nil, honorName: name, confidence: confidence)
    }
}

struct PhotoTileGroup: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var tiles: [PhotoTileToken]
}

struct PhotoRecognitionRequest: Hashable {
    var source: PhotoRecognitionSource = .sample
    var handPatternHint: PhotoHandPatternSuggestion = .unknown
    var note: String = ""
    var imageData: Data? = nil
}

struct PhotoRecognitionResult: Identifiable, Hashable {
    let id = UUID()
    var source: PhotoRecognitionSource
    var suggestedPattern: PhotoHandPatternSuggestion
    var tileGroups: [PhotoTileGroup]
    var confidence: Double
    var notes: [String]
    var croppedTileCount: Int = 0
    var createdAt: Date = .now
    
    var totalTileCount: Int {
        tileGroups.reduce(0) { $0 + $1.tiles.count }
    }
}
