import Foundation

protocol PhotoRecognitionService: Sendable {
    func recognize(request: PhotoRecognitionRequest) async throws -> PhotoRecognitionResult
}

enum PhotoRecognitionServiceError: Error, LocalizedError {
    case unsupportedInput
    case recognitionFailed
    
    var errorDescription: String? {
        switch self {
        case .unsupportedInput:
            return "当前输入类型暂不支持。"
        case .recognitionFailed:
            return "暂时无法识别这张牌面。"
        }
    }
}

struct MockPhotoRecognitionService: PhotoRecognitionService {
    func recognize(request: PhotoRecognitionRequest) async throws -> PhotoRecognitionResult {
        try await Task.sleep(nanoseconds: 250_000_000)
        
        let pattern = request.handPatternHint == .unknown ? .standard : request.handPatternHint
        let result: PhotoRecognitionResult
        
        switch pattern {
        case .unknown:
            result = PhotoRecognitionResult(
                source: request.source,
                suggestedPattern: .standard,
                regionResults: [],
                tileGroups: [
                    PhotoTileGroup(
                        title: "手牌",
                        tiles: [
                            .suited(.man, rank: 2), .suited(.man, rank: 3), .suited(.man, rank: 4),
                            .suited(.pin, rank: 2), .suited(.pin, rank: 3), .suited(.pin, rank: 4),
                            .suited(.sou, rank: 6), .suited(.sou, rank: 7), .suited(.sou, rank: 8),
                            .honor("东"), .honor("东"), .honor("中"),
                            .suited(.man, rank: 5)
                        ]
                    ),
                    PhotoTileGroup(
                        title: "和牌",
                        tiles: [.suited(.man, rank: 5)]
                    )
                ],
                confidence: 0.65,
                notes: ["未指定牌型提示时，先返回一组通用 mock 识别结果。"],
                postProcessWarnings: [],
                isStructurallyValid: true,
                croppedTileCount: 0,
                createdAt: .now
            )
        case .standard:
            result = PhotoRecognitionResult(
                source: request.source,
                suggestedPattern: .standard,
                regionResults: [],
                tileGroups: [
                    PhotoTileGroup(
                        title: "手牌",
                        tiles: [
                            .suited(.man, rank: 1), .suited(.man, rank: 2), .suited(.man, rank: 3),
                            .suited(.pin, rank: 4), .suited(.pin, rank: 5), .suited(.pin, rank: 6),
                            .suited(.sou, rank: 7), .suited(.sou, rank: 8), .suited(.sou, rank: 9),
                            .honor("东"), .honor("东"), .honor("白"),
                            .suited(.man, rank: 5)
                        ]
                    ),
                    PhotoTileGroup(
                        title: "和牌",
                        tiles: [
                            .suited(.man, rank: 5)
                        ]
                    )
                ],
                confidence: 0.82,
                notes: [
                    "这是 mock 结果，后续可以替换成真实图像识别服务。",
                    "当前只保留牌型结构骨架，不做实际 CV 推理。"
                ],
                postProcessWarnings: [],
                isStructurallyValid: true,
                croppedTileCount: 0,
                createdAt: .now
            )
        case .sevenPairs:
            result = PhotoRecognitionResult(
                source: request.source,
                suggestedPattern: .sevenPairs,
                regionResults: [],
                tileGroups: [
                    PhotoTileGroup(
                        title: "手牌",
                        tiles: [
                            .suited(.man, rank: 1), .suited(.man, rank: 1),
                            .suited(.man, rank: 2), .suited(.man, rank: 2),
                            .suited(.pin, rank: 3), .suited(.pin, rank: 3),
                            .suited(.pin, rank: 4), .suited(.pin, rank: 4),
                            .suited(.sou, rank: 5), .suited(.sou, rank: 5),
                            .honor("白"), .honor("白"),
                            .honor("发")
                        ]
                    ),
                    PhotoTileGroup(
                        title: "和牌",
                        tiles: [.honor("发")]
                    )
                ],
                confidence: 0.77,
                notes: ["示例按七对子组织，方便后续接入正式算分。"],
                postProcessWarnings: [],
                isStructurallyValid: true,
                croppedTileCount: 0,
                createdAt: .now
            )
        case .kokushi:
            result = PhotoRecognitionResult(
                source: request.source,
                suggestedPattern: .kokushi,
                regionResults: [],
                tileGroups: [
                    PhotoTileGroup(
                        title: "手牌",
                        tiles: [
                            .suited(.man, rank: 1), .suited(.man, rank: 9),
                            .suited(.pin, rank: 1), .suited(.pin, rank: 9),
                            .suited(.sou, rank: 1), .suited(.sou, rank: 9),
                            .honor("东"), .honor("南"), .honor("西"), .honor("北"),
                            .honor("白"), .honor("发"), .honor("中")
                        ]
                    ),
                    PhotoTileGroup(
                        title: "和牌",
                        tiles: [.suited(.man, rank: 1)]
                    )
                ],
                confidence: 0.88,
                notes: ["示例按国士无双组织，后续可进一步接入十三面判断。"],
                postProcessWarnings: [],
                isStructurallyValid: true,
                croppedTileCount: 0,
                createdAt: .now
            )
        case .triplet:
            result = PhotoRecognitionResult(
                source: request.source,
                suggestedPattern: .triplet,
                regionResults: [],
                tileGroups: [
                    PhotoTileGroup(
                        title: "手牌",
                        tiles: [
                            .suited(.man, rank: 3), .suited(.man, rank: 3), .suited(.man, rank: 3),
                            .suited(.pin, rank: 5), .suited(.pin, rank: 5), .suited(.pin, rank: 5),
                            .suited(.sou, rank: 7), .suited(.sou, rank: 7), .suited(.sou, rank: 7),
                            .honor("东"), .honor("东"), .honor("东"),
                            .honor("白")
                        ]
                    ),
                    PhotoTileGroup(
                        title: "和牌",
                        tiles: [.honor("白")]
                    )
                ],
                confidence: 0.79,
                notes: ["示例按对对和组织，适合作为手动校正的起点。"],
                postProcessWarnings: [],
                isStructurallyValid: true,
                croppedTileCount: 0,
                createdAt: .now
            )
        }
        
        return result
    }
}
