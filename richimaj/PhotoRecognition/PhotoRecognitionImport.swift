import Foundation

enum PhotoRecognitionImport {
    private static let autofillConfidenceThreshold = 0.9

    static func makeHandPatternDraft(from result: PhotoRecognitionResult) -> HandPatternDraft? {
        let groups = filteredGroups(from: result)
        var draft = HandPatternDraft()
        let imported = importedDraftComponents(from: groups)

        draft.handCounts = imported.handCounts
        draft.openCounts = imported.openCounts
        draft.openMeldGroups = imported.openMeldGroups
        draft.winningTile = imported.winningTile
        let importedTileCount =
            imported.handCounts.values.reduce(0, +)
            + imported.openCounts.values.reduce(0, +)
            + (imported.winningTile == nil ? 0 : 1)
        return importedTileCount > 0 ? draft : nil
    }

    private static func filteredGroups(from result: PhotoRecognitionResult) -> [PhotoTileGroup] {
        let groups = !result.tileGroups.isEmpty ? result.tileGroups : fallbackGroups(from: result.regionResults)
        return groups.compactMap { group in
            let filteredTiles = group.tiles.filter { $0.confidence > autofillConfidenceThreshold }
            guard !filteredTiles.isEmpty else { return nil }
            return PhotoTileGroup(title: group.title, tiles: filteredTiles)
        }
    }

    private static func importedDraftComponents(from groups: [PhotoTileGroup]) -> (
        handCounts: [MahjongTile: Int],
        openCounts: [MahjongTile: Int],
        openMeldGroups: [OpenMeldGroup],
        winningTile: MahjongTile?
    ) {
        var handCounts: [MahjongTile: Int] = [:]
        var openCounts: [MahjongTile: Int] = [:]
        var openMeldGroups: [OpenMeldGroup] = []
        var winningTile: MahjongTile?

        for group in groups {
            if group.title == "和牌" {
                winningTile = group.tiles.compactMap { token in
                    tile(from: token)
                }.first
            } else if group.title.hasPrefix("副露") {
                let tiles = group.tiles.compactMap { token in
                    tile(from: token)
                }
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

        return (handCounts, openCounts, openMeldGroups, winningTile)
    }

    private static func fallbackGroups(from regions: [PhotoRecognitionRegionResult]) -> [PhotoTileGroup] {
        var groups: [PhotoTileGroup] = []
        if let hand = regions.first(where: { $0.regionKey == "hand" }), !hand.tiles.isEmpty {
            groups.append(PhotoTileGroup(title: "手牌", tiles: hand.tiles))
        }
        if let open = regions.first(where: { $0.regionKey == "openMelds" }), !open.tiles.isEmpty {
            groups.append(PhotoTileGroup(title: "副露1", tiles: open.tiles))
        }
        if let winning = regions.first(where: { $0.regionKey == "winning" }),
           let tile = winning.tiles.first {
            groups.append(PhotoTileGroup(title: "和牌", tiles: [tile]))
        }
        return groups
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
