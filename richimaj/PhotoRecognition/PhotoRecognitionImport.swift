import Foundation

@MainActor
enum PhotoRecognitionImport {
    static func makeHandPatternDraft(from result: PhotoRecognitionResult) -> HandPatternDraft? {
        var draft = HandPatternDraft()
        var handCounts: [MahjongTile: Int] = [:]
        var openCounts: [MahjongTile: Int] = [:]
        var openMeldGroups: [OpenMeldGroup] = []
        var winningTile: MahjongTile?
        
        for group in result.tileGroups {
            if group.title == "和牌" {
                winningTile = group.tiles.compactMap(tile(from:)).first
            } else if group.title.hasPrefix("副露") {
                let tiles = group.tiles.compactMap(tile(from:))
                for tile in tiles {
                    openCounts[tile, default: 0] += 1
                }
                if let meldGroup = openMeldGroup(from: tiles) {
                    openMeldGroups.append(meldGroup)
                }
            } else {
                for token in group.tiles {
                    guard let tile = tile(from: token) else { continue }
                    handCounts[tile, default: 0] += 1
                }
            }
        }
        
        guard !handCounts.isEmpty, let winningTile else { return nil }
        draft.handCounts = handCounts
        draft.openCounts = openCounts
        draft.openMeldGroups = openMeldGroups
        draft.winningTile = winningTile
        return draft
    }
    
    private static func openMeldGroup(from tiles: [MahjongTile]) -> OpenMeldGroup? {
        if tiles.count == 4, Set(tiles).count == 1 {
            return OpenMeldGroup(type: .openKan, tiles: tiles)
        }
        if tiles.count == 3, Set(tiles).count == 1 {
            return OpenMeldGroup(type: .pon, tiles: tiles)
        }
        if tiles.count == 3 {
            let sorted = tiles.sorted { $0.rawValue < $1.rawValue }
            if let suit = sorted.first?.suitIndex,
               sorted.allSatisfy({ $0.suitIndex == suit }),
               let first = sorted.first?.number,
               sorted[1].number == first + 1,
               sorted[2].number == first + 2 {
                return OpenMeldGroup(type: .chi, tiles: sorted)
            }
        }
        return nil
    }
    
    private static func tile(from token: PhotoTileToken) -> MahjongTile? {
        switch token.suit {
        case .man:
            guard let rank = token.rank else { return nil }
            return MahjongTile(rawValue: rank - 1)
        case .pin:
            guard let rank = token.rank else { return nil }
            return MahjongTile(rawValue: 9 + rank - 1)
        case .sou:
            guard let rank = token.rank else { return nil }
            return MahjongTile(rawValue: 18 + rank - 1)
        case .honor:
            switch token.honorName {
            case "东": return .east
            case "南": return .south
            case "西": return .west
            case "北": return .north
            case "白": return .white
            case "发": return .green
            case "中": return .red
            default: return nil
            }
        }
    }
}
