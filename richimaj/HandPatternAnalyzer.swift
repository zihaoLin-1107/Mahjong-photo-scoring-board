//
//  HandPatternAnalyzer.swift
//  richimaj
//
//  Created by Codex on 2026/4/2.
//

import Foundation

struct HandPatternAnalyzer {
    var draft: HandPatternDraft
    var winType: WinType
    var selectedCircumstantialYaku: Set<CircumstantialYaku>
    var seatWindIndex: Int
    var roundWindIndex: Int
    var riichiYaku: RiichiYakuKind
    
    func analyze(winningTile: MahjongTile) -> PatternDetectionResult? {
        guard totalTileCount == requiredTileCountBeforeWin else { return nil }
        guard hasValidOpenMeldStructure else { return nil }

        let fullCounts = combinedCounts(with: winningTile)
        let concealedKanGroups = draft.concealedKanTiles.map { tile in
            OpenMeldGroup(type: .concealedKan, tiles: [tile, tile, tile, tile])
        }
        let context = HandAnalysisContext(openMeldGroups: draft.openMeldGroups + concealedKanGroups)
        guard let structuralCounts = structuralCountsForAnalysis(fullCounts, context: context) else {
            return nil
        }
        let hasOpenMelds = draft.openMeldGroups.contains { $0.type != .concealedKan }
        
        if !hasOpenMelds, let kokushiResult = kokushiDetectionResult(fullCounts: fullCounts, winningTile: winningTile) {
            return applyBonusHan(to: applyCircumstantialYaku(to: applyRiichiDisplayIfNeeded(to: kokushiResult, hasOpenMelds: hasOpenMelds)))
        }
        
        if totalKongCount == 4 {
            return applyBonusHan(to: applyCircumstantialYaku(to: PatternDetectionResult(
                han: 13,
                fu: 0,
                yakuNames: ["四杠子"],
                notes: [
                    "四杠子按役满处理。",
                    "当前最小版本对四杠子的其他复合役未继续叠加。"
                ],
                yakumanMultiplier: 1
            )))
        }
        
        if !hasOpenMelds && isSevenPairs(structuralCounts) {
            var yakuNames = ["七对子"]
            var han = 2
            let notes = ["七对子固定 25 符。", "这版牌型输入目前只按门前手识别。"]
            
            if let riichiName = riichiYaku.yakuName, !hasOpenMelds {
                yakuNames.append(riichiName)
                han += riichiYaku.hanValue
            }

            if winType == .tsumo {
                yakuNames.append("门前清自摸和")
                han += 1
            }
            
            if isTanyao(fullCounts) {
                yakuNames.append("断幺九")
                han += 1
            }
            if isHonitsu(fullCounts) {
                yakuNames.append("混一色")
                han += 3
            }
            if isChinitsu(fullCounts) {
                yakuNames.append("清一色")
                han += 6
            }
            if han >= 13 {
                return applyCircumstantialYaku(to: PatternDetectionResult(
                    han: han,
                    fu: 25,
                    yakuNames: yakuNames,
                    notes: ["按常见算え役満口径，累计 13 番以上按役满处理。"] + notes
                ))
            }
            return applyBonusHan(to: applyCircumstantialYaku(to: PatternDetectionResult(
                han: han,
                fu: 25,
                yakuNames: yakuNames,
                notes: notes
            )))
        }
        
        let candidates = standardHandCandidates(
            counts: structuralCounts,
            winningTile: winningTile.rawValue
        )
        guard !candidates.isEmpty else { return nil }
        
        let analyses = candidates.compactMap { candidate in
            analyzeCandidate(candidate, fullCounts: fullCounts, hasOpenMelds: hasOpenMelds, context: context)
        }
        
        if analyses.isEmpty {
            guard let fallback = candidates.max(by: { lhs, rhs in
                calculateFu(lhs, hasOpenMelds: hasOpenMelds, context: context)
                < calculateFu(rhs, hasOpenMelds: hasOpenMelds, context: context)
            }) else {
                return nil
            }
            
            return applyBonusHan(to: applyCircumstantialYaku(to: PatternDetectionResult(
                han: 0,
                fu: calculateFu(fallback, hasOpenMelds: hasOpenMelds, context: context),
                yakuNames: ["无役"],
                notes: ["条件役：海底捞月、河底捞鱼"]
            )))
        }
        
        guard let best = analyses.max(by: { lhs, rhs in
            if lhs.han == rhs.han {
                return lhs.fu < rhs.fu
            }
            return lhs.han < rhs.han
        }) else {
            return nil
        }
        
        return applyBonusHan(to: applyCircumstantialYaku(to: best))
    }
    
    func applyBonusHan(to result: PatternDetectionResult) -> PatternDetectionResult {
        let bonusHan = draft.doraCount + draft.redDoraCount
        guard bonusHan > 0 else { return result }
        
        if result.yakumanMultiplier > 0 {
            return PatternDetectionResult(
                han: result.han,
                fu: result.fu,
                yakuNames: result.yakuNames,
                notes: result.notes + ["已记录宝牌 \(draft.doraCount) 番、红宝牌 \(draft.redDoraCount) 番；役满牌型不再额外叠加宝牌番数。"],
                yakumanMultiplier: result.yakumanMultiplier
            )
        }
        
        var yakuNames = result.yakuNames
        if draft.doraCount > 0 {
            yakuNames.append("宝牌 x\(draft.doraCount)")
        }
        if draft.redDoraCount > 0 {
            yakuNames.append("红宝牌 x\(draft.redDoraCount)")
        }
        
        return PatternDetectionResult(
            han: result.han + bonusHan,
            fu: result.fu,
            yakuNames: yakuNames,
            notes: result.notes + ["已计入宝牌 \(draft.doraCount) 番、红宝牌 \(draft.redDoraCount) 番。"],
            yakumanMultiplier: result.yakumanMultiplier
        )
    }

    func applyRiichiDisplayIfNeeded(to result: PatternDetectionResult, hasOpenMelds: Bool) -> PatternDetectionResult {
        guard let riichiName = riichiYaku.yakuName, !hasOpenMelds else { return result }
        guard !result.yakuNames.contains(riichiName) else { return result }
        return PatternDetectionResult(
            han: result.yakumanMultiplier > 0 ? result.han : result.han + riichiYaku.hanValue,
            fu: result.fu,
            yakuNames: result.yakuNames + [riichiName],
            notes: result.notes,
            yakumanMultiplier: result.yakumanMultiplier
        )
    }
    
    func applyCircumstantialYaku(to result: PatternDetectionResult) -> PatternDetectionResult {
        guard !selectedCircumstantialYaku.isEmpty else { return result }
        let extraNames = CircumstantialYaku.allCases
            .filter { selectedCircumstantialYaku.contains($0) }
            .map(\.rawValue)

        let filteredNotes = result.notes.filter { !$0.hasPrefix("条件役：") }

        if result.yakumanMultiplier > 0 {
            return PatternDetectionResult(
                han: result.han,
                fu: result.fu,
                yakuNames: result.yakuNames + extraNames,
                notes: filteredNotes,
                yakumanMultiplier: result.yakumanMultiplier
            )
        }
        let baseYakuNames = result.yakuNames == ["无役"] ? [] : result.yakuNames
        return PatternDetectionResult(
            han: result.han + extraNames.count,
            fu: result.fu,
            yakuNames: baseYakuNames + extraNames,
            notes: filteredNotes,
            yakumanMultiplier: result.yakumanMultiplier
        )
    }
    
    func combinedCounts(with winningTile: MahjongTile) -> [Int] {
        var counts = Array(repeating: 0, count: MahjongTile.allCases.count)
        for (tile, count) in draft.handCounts {
            counts[tile.rawValue] = count
        }
        for (tile, count) in draft.openCounts {
            counts[tile.rawValue] += count
        }
        counts[winningTile.rawValue] += 1
        return counts
    }
    
    func normalizedCountsForStructure(_ counts: [Int]) -> [Int] {
        counts
    }

    func structuralCountsForAnalysis(_ counts: [Int], context: HandAnalysisContext) -> [Int]? {
        var normalized = normalizedCountsForStructure(counts)
        for meld in context.openMeldGroups {
            for tileIndex in meld.structuralTiles {
                guard normalized.indices.contains(tileIndex), normalized[tileIndex] > 0 else {
                    return nil
                }
                normalized[tileIndex] -= 1
            }
        }
        return normalized
    }
    
    func isSevenPairs(_ counts: [Int]) -> Bool {
        counts.filter { $0 == 2 }.count == 7
    }
    
    func standardHandCandidates(counts: [Int], winningTile: Int) -> [StandardHandCandidate] {
        var candidates: [StandardHandCandidate] = []
        for pairIndex in counts.indices where counts[pairIndex] >= 2 {
            var remaining = counts
            remaining[pairIndex] -= 2
            var groups: [HandGroup] = []
            var allGroupSets: [[HandGroup]] = []
            buildGroups(counts: &remaining, current: &groups, results: &allGroupSets)
            for groupSet in allGroupSets {
                let possibleWaits = waitKinds(pairTile: pairIndex, groups: groupSet, winningTile: winningTile)
                for wait in possibleWaits {
                    candidates.append(StandardHandCandidate(pairTile: pairIndex, groups: groupSet, waitKind: wait))
                }
            }
        }
        return candidates
    }
    
    func buildGroups(counts: inout [Int], current: inout [HandGroup], results: inout [[HandGroup]]) {
        guard let firstIndex = counts.firstIndex(where: { $0 > 0 }) else {
            results.append(current)
            return
        }
        if counts[firstIndex] >= 3 {
            counts[firstIndex] -= 3
            current.append(HandGroup(kind: .triplet, tiles: [firstIndex, firstIndex, firstIndex]))
            buildGroups(counts: &counts, current: &current, results: &results)
            current.removeLast()
            counts[firstIndex] += 3
        }
        if firstIndex < 27 {
            let rank = firstIndex % 9
            if rank <= 6, counts[firstIndex + 1] > 0, counts[firstIndex + 2] > 0 {
                counts[firstIndex] -= 1
                counts[firstIndex + 1] -= 1
                counts[firstIndex + 2] -= 1
                current.append(HandGroup(kind: .sequence, tiles: [firstIndex, firstIndex + 1, firstIndex + 2]))
                buildGroups(counts: &counts, current: &current, results: &results)
                current.removeLast()
                counts[firstIndex] += 1
                counts[firstIndex + 1] += 1
                counts[firstIndex + 2] += 1
            }
        }
    }
    
    func waitKinds(pairTile: Int, groups: [HandGroup], winningTile: Int) -> [WaitKind] {
        var waits: [WaitKind] = []
        if pairTile == winningTile {
            waits.append(.tanki)
        }
        for group in groups {
            guard group.tiles.contains(winningTile) else { continue }
            switch group.kind {
            case .triplet:
                waits.append(.shanpon)
            case .sequence:
                let start = group.tiles[0]
                let startRank = start % 9 + 1
                if winningTile == group.tiles[1] {
                    waits.append(.kanchan)
                } else if winningTile == group.tiles[0] {
                    waits.append(startRank == 7 ? .penchan : .ryanmen)
                } else if winningTile == group.tiles[2] {
                    waits.append(startRank == 1 ? .penchan : .ryanmen)
                }
            }
        }
        return waits.isEmpty ? [.shanpon] : waits
    }
    
    func analyzeCandidate(_ candidate: StandardHandCandidate, fullCounts: [Int], hasOpenMelds: Bool, context: HandAnalysisContext) -> PatternDetectionResult? {
        var yakuNames: [String] = []
        var han = 0
        let allGroups = context.openHandGroups + candidate.groups
        
        if let riichiName = riichiYaku.yakuName, !hasOpenMelds {
            yakuNames.append(riichiName)
            han += riichiYaku.hanValue
        }
        if winType == .tsumo && !hasOpenMelds {
            yakuNames.append("门前清自摸和")
            han += 1
        }
        if isTanyao(fullCounts) {
            yakuNames.append("断幺九")
            han += 1
        }
        let yakuhaiNames = yakuhaiYakuNames(allGroups)
        if !yakuhaiNames.isEmpty {
            yakuNames.append(contentsOf: yakuhaiNames)
            han += yakuhaiNames.count
        }
        if !hasOpenMelds && isPinfu(candidate) {
            yakuNames.append("平和")
            han += 1
        }
        if !hasOpenMelds && isIipeikou(allGroups) {
            yakuNames.append("一杯口")
            han += 1
        }
        if isToitoi(allGroups) {
            yakuNames.append("对对和")
            han += 2
        }
        if totalKongCount == 3 {
            yakuNames.append("三杠子")
            han += 2
        }
        if isSanshokuDoujun(allGroups) {
            yakuNames.append("三色同顺")
            han += hasOpenMelds ? 1 : 2
        }
        if isIttsu(allGroups) {
            yakuNames.append("一气通贯")
            han += hasOpenMelds ? 1 : 2
        }
        if isSanankou(candidate.groups) {
            yakuNames.append("三暗刻")
            han += 2
        }
        if isShousangen(allGroups, pairTile: candidate.pairTile) {
            yakuNames.append("小三元")
            han += 2
        }
        if !hasOpenMelds && isSuuankou(candidate.groups) {
            let isSingleWait = candidate.waitKind == .tanki
            return applyRiichiDisplayIfNeeded(to: PatternDetectionResult(
                han: isSingleWait ? 26 : 13,
                fu: 0,
                yakuNames: [isSingleWait ? "四暗刻单骑" : "四暗刻"],
                notes: [isSingleWait ? "四暗刻单骑按双役满处理。" : "四暗刻按役满处理。"],
                yakumanMultiplier: isSingleWait ? 2 : 1
            ), hasOpenMelds: hasOpenMelds)
        }
        if isDaisangen(allGroups) {
            return applyRiichiDisplayIfNeeded(to: PatternDetectionResult(han: 13, fu: 0, yakuNames: ["大三元"], notes: ["大三元按役满处理。"], yakumanMultiplier: 1), hasOpenMelds: hasOpenMelds)
        }
        if isTsuuiisou(fullCounts) {
            return applyRiichiDisplayIfNeeded(to: PatternDetectionResult(han: 13, fu: 0, yakuNames: ["字一色"], notes: ["字一色按役满处理。"], yakumanMultiplier: 1), hasOpenMelds: hasOpenMelds)
        }
        if isChinroutou(fullCounts) {
            return applyRiichiDisplayIfNeeded(to: PatternDetectionResult(han: 13, fu: 0, yakuNames: ["清老头"], notes: ["清老头按役满处理。"], yakumanMultiplier: 1), hasOpenMelds: hasOpenMelds)
        }
        if isShousuushii(allGroups, pairTile: candidate.pairTile) {
            return applyRiichiDisplayIfNeeded(to: PatternDetectionResult(han: 13, fu: 0, yakuNames: ["小四喜"], notes: ["小四喜按役满处理。"], yakumanMultiplier: 1), hasOpenMelds: hasOpenMelds)
        }
        if isDaisuushii(allGroups) {
            return applyRiichiDisplayIfNeeded(to: PatternDetectionResult(han: 26, fu: 0, yakuNames: ["大四喜"], notes: ["大四喜按双役满处理。"], yakumanMultiplier: 2), hasOpenMelds: hasOpenMelds)
        }
        if isHonitsu(fullCounts) {
            yakuNames.append("混一色")
            han += hasOpenMelds ? 2 : 3
        }
        if isChinitsu(fullCounts) {
            yakuNames.append("清一色")
            han += hasOpenMelds ? 5 : 6
        }
        if isHonroutou(fullCounts) {
            yakuNames.append("混老头")
            han += 2
        }
        guard !yakuNames.isEmpty else { return nil }
        let fu = calculateFu(candidate, hasOpenMelds: hasOpenMelds, context: context)
        var notes = [
            hasOpenMelds ? "当前副露版仍是简化识别，明暗刻与杠的符数建议回正式算分页手动复核。" : "当前最小版本只按门前手识别，未自动计入立直、一发、宝牌、里宝牌、杠宝牌。",
            "累计 13 番以上按常见算え役満口径处理。"
        ]
        if han >= 13 {
            notes.append("这手按累计役满口径结算。")
        }
        return PatternDetectionResult(han: han, fu: fu, yakuNames: yakuNames, notes: notes)
    }
    
    func calculateFu(_ candidate: StandardHandCandidate, hasOpenMelds: Bool, context: HandAnalysisContext) -> Int {
        if !hasOpenMelds && isPinfu(candidate) && winType == .tsumo {
            return 20
        }
        var fu = 20
        if winType == .tsumo && !hasOpenMelds {
            fu += 2
        } else if !hasOpenMelds {
            fu += 10
        }
        if isValuePair(candidate.pairTile) {
            fu += 2
        }
        for group in context.openHandGroups where group.kind == .triplet {
            let tile = MahjongTile(rawValue: group.tiles[0])!
            if isOpenKongTile(group.tiles[0]) {
                fu += tile.isTerminalOrHonor ? 16 : 8
            } else {
                fu += tile.isTerminalOrHonor ? 4 : 2
            }
        }
        for group in candidate.groups where group.kind == .triplet {
            let tile = MahjongTile(rawValue: group.tiles[0])!
            if isConcealedKongTile(group.tiles[0]) {
                fu += tile.isTerminalOrHonor ? 32 : 16
            } else if isOpenKongTile(group.tiles[0]) {
                fu += tile.isTerminalOrHonor ? 16 : 8
            } else {
                fu += tile.isTerminalOrHonor ? (hasOpenMelds ? 4 : 8) : (hasOpenMelds ? 2 : 4)
            }
        }
        switch candidate.waitKind {
        case .tanki, .kanchan, .penchan:
            fu += 2
        case .ryanmen, .shanpon:
            break
        }
        if !hasOpenMelds && isPinfu(candidate) && winType == .ron {
            return 30
        }
        return ((fu + 9) / 10) * 10
    }
    
    func isPinfu(_ candidate: StandardHandCandidate) -> Bool {
        candidate.groups.allSatisfy { $0.kind == .sequence }
            && !isValuePair(candidate.pairTile)
            && candidate.waitKind == .ryanmen
    }
    
    func isIipeikou(_ groups: [HandGroup]) -> Bool {
        let sequences = groups.filter { $0.kind == .sequence }.map { $0.tiles }
        var seen: [[Int]: Int] = [:]
        for sequence in sequences {
            seen[sequence, default: 0] += 1
        }
        return seen.values.contains(where: { $0 >= 2 })
    }
    
    func isToitoi(_ groups: [HandGroup]) -> Bool { groups.allSatisfy { $0.kind == .triplet } }
    
    func isSanshokuDoujun(_ groups: [HandGroup]) -> Bool {
        let starts = groups.filter { $0.kind == .sequence }.compactMap { group -> (Int, Int)? in
            guard let tile = MahjongTile(rawValue: group.tiles[0]),
                  let suit = tile.suitIndex,
                  let number = tile.number else { return nil }
            return (number, suit)
        }
        for number in 1...7 {
            let suits = starts.filter { $0.0 == number }.map { $0.1 }
            if Set(suits) == Set([0, 1, 2]) { return true }
        }
        return false
    }
    
    func isIttsu(_ groups: [HandGroup]) -> Bool {
        let sequences = groups.filter { $0.kind == .sequence }
        for suit in 0...2 {
            let needed = Set([1, 4, 7])
            let starts = Set(sequences.compactMap { group -> Int? in
                guard let tile = MahjongTile(rawValue: group.tiles[0]), tile.suitIndex == suit else { return nil }
                return tile.number
            })
            if needed.isSubset(of: starts) { return true }
        }
        return false
    }
    
    func isSanankou(_ concealedGroups: [HandGroup]) -> Bool {
        concealedGroups.filter { $0.kind == .triplet }.count >= 3
    }
    
    func isSuuankou(_ concealedGroups: [HandGroup]) -> Bool {
        concealedGroups.filter { $0.kind == .triplet }.count == 4
    }
    
    func isShousangen(_ groups: [HandGroup], pairTile: Int) -> Bool {
        let dragonTriplets = groups.filter { $0.kind == .triplet && isDragonTile($0.tiles[0]) }.count
        return dragonTriplets == 2 && isDragonTile(pairTile)
    }
    
    func isDaisangen(_ groups: [HandGroup]) -> Bool {
        let dragonSet = Set(groups.filter { $0.kind == .triplet }.map { $0.tiles[0] }).intersection([
            MahjongTile.white.rawValue,
            MahjongTile.green.rawValue,
            MahjongTile.red.rawValue
        ])
        return dragonSet.count == 3
    }
    
    func isTsuuiisou(_ counts: [Int]) -> Bool {
        counts.indices.allSatisfy { index in
            counts[index] == 0 || MahjongTile(rawValue: index)!.isHonor
        }
    }
    
    func isChinroutou(_ counts: [Int]) -> Bool {
        counts.indices.allSatisfy { index in
            counts[index] == 0 || MahjongTile(rawValue: index)!.isTerminal
        }
    }
    
    func isShousuushii(_ groups: [HandGroup], pairTile: Int) -> Bool {
        let windTriplets = groups.filter { $0.kind == .triplet && isWindTile($0.tiles[0]) }.count
        return windTriplets == 3 && isWindTile(pairTile)
    }
    
    func isDaisuushii(_ groups: [HandGroup]) -> Bool {
        let windSet = Set(groups.filter { $0.kind == .triplet }.map { $0.tiles[0] }).intersection([
            MahjongTile.east.rawValue,
            MahjongTile.south.rawValue,
            MahjongTile.west.rawValue,
            MahjongTile.north.rawValue
        ])
        return windSet.count == 4
    }
    
    func isTanyao(_ counts: [Int]) -> Bool {
        for index in counts.indices where counts[index] > 0 {
            let tile = MahjongTile(rawValue: index)!
            if tile.isTerminalOrHonor { return false }
        }
        return true
    }
    
    func isHonitsu(_ counts: [Int]) -> Bool {
        let suits = Set(counts.indices.compactMap { index -> Int? in
            guard counts[index] > 0 else { return nil }
            return MahjongTile(rawValue: index)?.suitIndex
        })
        let hasHonor = counts.indices.contains { index in
            counts[index] > 0 && MahjongTile(rawValue: index)!.isHonor
        }
        return suits.count == 1 && hasHonor
    }
    
    func isChinitsu(_ counts: [Int]) -> Bool {
        let suits = Set(counts.indices.compactMap { index -> Int? in
            guard counts[index] > 0 else { return nil }
            return MahjongTile(rawValue: index)?.suitIndex
        })
        let hasHonor = counts.indices.contains { index in
            counts[index] > 0 && MahjongTile(rawValue: index)!.isHonor
        }
        return suits.count == 1 && !hasHonor
    }
    
    func isHonroutou(_ counts: [Int]) -> Bool {
        for index in counts.indices where counts[index] > 0 {
            let tile = MahjongTile(rawValue: index)!
            if !tile.isTerminalOrHonor { return false }
        }
        return true
    }
    
    func valueTileHan(for tileIndex: Int) -> Int {
        guard let tile = MahjongTile(rawValue: tileIndex) else { return 0 }
        switch tile {
        case .white, .green, .red:
            return 1
        case .east, .south, .west, .north:
            var han = 0
            if seatWindIndex == tileIndex { han += 1 }
            if roundWindIndex == tileIndex { han += 1 }
            return han
        default:
            return 0
        }
    }

    func yakuhaiYakuNames(_ groups: [HandGroup]) -> [String] {
        var names: [String] = []
        for group in groups where group.kind == .triplet {
            names.append(contentsOf: valueTileYakuNames(for: group.tiles[0]))
        }
        return names
    }

    func valueTileYakuNames(for tileIndex: Int) -> [String] {
        guard let tile = MahjongTile(rawValue: tileIndex) else { return [] }
        switch tile {
        case .white:
            return ["白"]
        case .green:
            return ["发"]
        case .red:
            return ["中"]
        case .east, .south, .west, .north:
            var names: [String] = []
            if seatWindIndex == tileIndex {
                names.append("自风\(tile.label)")
            }
            if roundWindIndex == tileIndex {
                names.append("场风\(tile.label)")
            }
            return names
        default:
            return []
        }
    }
    
    func isDragonTile(_ tileIndex: Int) -> Bool {
        tileIndex == MahjongTile.white.rawValue
            || tileIndex == MahjongTile.green.rawValue
            || tileIndex == MahjongTile.red.rawValue
    }
    
    func isWindTile(_ tileIndex: Int) -> Bool {
        tileIndex == MahjongTile.east.rawValue
            || tileIndex == MahjongTile.south.rawValue
            || tileIndex == MahjongTile.west.rawValue
            || tileIndex == MahjongTile.north.rawValue
    }
    
    func isValuePair(_ tileIndex: Int) -> Bool {
        valueTileHan(for: tileIndex) > 0
    }
    
    func isConcealedKongTile(_ tileIndex: Int) -> Bool {
        guard let tile = MahjongTile(rawValue: tileIndex) else { return false }
        return draft.concealedKanTiles.contains(tile)
            || draft.openMeldGroups.contains(where: { $0.type == .concealedKan && $0.tiles.allSatisfy { $0 == tile } })
    }
    
    func isOpenKongTile(_ tileIndex: Int) -> Bool {
        guard let tile = MahjongTile(rawValue: tileIndex) else { return false }
        return draft.openMeldGroups.contains(where: { $0.type == .openKan && $0.tiles.allSatisfy { $0 == tile } })
    }
    
    func kokushiDetectionResult(fullCounts: [Int], winningTile: MahjongTile) -> PatternDetectionResult? {
        let yaochuIndices = [
            MahjongTile.man1.rawValue, MahjongTile.man9.rawValue,
            MahjongTile.pin1.rawValue, MahjongTile.pin9.rawValue,
            MahjongTile.sou1.rawValue, MahjongTile.sou9.rawValue,
            MahjongTile.east.rawValue, MahjongTile.south.rawValue,
            MahjongTile.west.rawValue, MahjongTile.north.rawValue,
            MahjongTile.white.rawValue, MahjongTile.green.rawValue,
            MahjongTile.red.rawValue
        ]
        for index in fullCounts.indices where fullCounts[index] > 0 && !yaochuIndices.contains(index) {
            return nil
        }
        guard yaochuIndices.allSatisfy({ fullCounts[$0] >= 1 }) else { return nil }
        let pairCount = yaochuIndices.filter { fullCounts[$0] >= 2 }.count
        guard pairCount == 1 else { return nil }
        let concealedCounts = combinedCountsBeforeWinningTile()
        let isThirteenSided = yaochuIndices.allSatisfy({ concealedCounts[$0] == 1 }) && yaochuIndices.contains(winningTile.rawValue)
        return PatternDetectionResult(
            han: isThirteenSided ? 26 : 13,
            fu: 0,
            yakuNames: [isThirteenSided ? "国士无双十三面" : "国士无双"],
            notes: [
                isThirteenSided ? "已识别为国士无双十三面。" : "已识别为国士无双。",
                isThirteenSided ? "国士无双十三面按双役满处理。" : "国士无双按役满处理。"
            ],
            yakumanMultiplier: isThirteenSided ? 2 : 1
        )
    }
    
    func combinedCountsBeforeWinningTile() -> [Int] {
        var counts = Array(repeating: 0, count: MahjongTile.allCases.count)
        for (tile, count) in draft.handCounts {
            counts[tile.rawValue] = count
        }
        for (tile, count) in draft.openCounts {
            counts[tile.rawValue] += count
        }
        return counts
    }
    
    var totalTileCount: Int {
        draft.handCounts.values.reduce(0, +) + draft.openCounts.values.reduce(0, +)
    }
    
    var concealedKongCount: Int {
        draft.concealedKanTiles.count
    }
    
    var openKongCount: Int {
        draft.openMeldGroups.filter { $0.type == .openKan }.count
    }
    
    var totalKongCount: Int {
        concealedKongCount + openKongCount
    }
    
    var requiredTileCountBeforeWin: Int {
        13 + totalKongCount
    }

    var hasValidOpenMeldStructure: Bool {
        if draft.openCounts.isEmpty {
            return draft.openMeldGroups.isEmpty
        }

        var coveredCounts: [MahjongTile: Int] = [:]
        for group in draft.openMeldGroups {
            for tile in group.tiles {
                coveredCounts[tile, default: 0] += 1
            }
        }

        let normalizedOpenCounts = draft.openCounts.filter { $0.value > 0 }
        let normalizedCoveredCounts = coveredCounts.filter { $0.value > 0 }
        return normalizedOpenCounts == normalizedCoveredCounts
    }
    
    func structuralTiles(for group: OpenMeldGroup) -> [Int] {
        switch group.type {
        case .chi:
            return group.tiles.map(\.rawValue)
        case .pon, .openKan, .concealedKan:
            guard let first = group.tiles.first else { return [] }
            return [first.rawValue, first.rawValue, first.rawValue]
        }
    }
    
    func handGroup(for group: OpenMeldGroup) -> HandGroup? {
        switch group.type {
        case .chi:
            return HandGroup(kind: .sequence, tiles: structuralTiles(for: group))
        case .pon, .openKan, .concealedKan:
            return HandGroup(kind: .triplet, tiles: structuralTiles(for: group))
        }
    }
}
