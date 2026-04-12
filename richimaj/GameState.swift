//
//  GameState.swift
//  richimaj
//
//  Created by Codex on 2026/4/1.
//

import Foundation
import Combine

struct PlayerScore: Identifiable {
    let id = UUID()
    var name: String
    var nickname: String
    var score: Int
    var position: String
    var isRiichi = false
}

enum WinType: String, CaseIterable, Identifiable {
    case tsumo = "自摸"
    case ron = "荣和"
    
    var id: String { rawValue }
}

struct FormalScoreResult {
    var winnerIndex: Int
    var loserIndex: Int?
    var winType: WinType
    var isEastWin: Bool
    var han: Int
    var fu: Int
    var honbaCount: Int
    var riichiStickCount: Int
    var winnerGain: Int
    var loserPayment: Int?
    var dealerPayment: Int?
    var nonDealerPayment: Int?
    var yakumanMultiplier: Int = 0
    var limitName: String? = nil
    
    var riichiBonus: Int {
        riichiStickCount * 1000
    }
}

struct QuickRonSettlement {
    var winnerIndex: Int
    var points: Int
}

final class GameState: ObservableObject {
    let defaultPointInput = "3900"
    let defaultNicknames = ["下", "右", "上", "左"]
    let roundWinds = ["东", "南"]
    let initialPlayers: [PlayerScore] = [
        PlayerScore(name: "东家", nickname: "下", score: 25000, position: "下"),
        PlayerScore(name: "南家", nickname: "右", score: 25000, position: "右"),
        PlayerScore(name: "西家", nickname: "上", score: 25000, position: "上"),
        PlayerScore(name: "北家", nickname: "左", score: 25000, position: "左")
    ]
    
    @Published var players: [PlayerScore]
    @Published var roundWindIndex = 0
    @Published var roundNumber = 1
    @Published var honbaCount = 0
    @Published var riichiStickCount = 0
    @Published var lastWinType: WinType = .ron
    @Published var lastPointInput = "3900"
    @Published var lastEnteredNicknames = ["", "", "", ""]
    @Published var isMatchFinished = false
    
    let multipleRonRule = MultipleRonRule.commonOnlinePlatform
    
    init() {
        players = initialPlayers
    }
    
    var roundText: String {
        if isMatchFinished {
            return "比赛结束"
        }
        
        return "\(roundWinds[roundWindIndex])\(roundNumber)局"
    }
    
    func isEastPlayer(_ index: Int) -> Bool {
        guard players.indices.contains(index) else { return false }
        return players[index].name == "东家"
    }
    
    func declareRiichi(for index: Int) {
        guard players.indices.contains(index) else { return }
        guard players[index].score >= 1000 else { return }
        guard !players[index].isRiichi else { return }
        
        players[index].score -= 1000
        players[index].isRiichi = true
        riichiStickCount += 1
    }
    
    func clearRiichiState() {
        for index in players.indices {
            players[index].isRiichi = false
        }
    }
    
    func settleWin(winnerIndex: Int, loserIndex: Int?, winType: WinType, points: Int) -> Bool {
        guard !isMatchFinished else { return false }
        guard players.indices.contains(winnerIndex) else { return false }
        let eastWin = isEastPlayer(winnerIndex)
        let dealerChanged = !eastWin
        
        let riichiBonus = riichiStickCount * 1000
        
        switch winType {
        case .ron:
            guard let loserIndex, players.indices.contains(loserIndex) else { return false }
            players[winnerIndex].score += points + riichiBonus
            players[loserIndex].score -= points
            
        case .tsumo:
            let paymentPerPlayer = points / 3
            var totalGain = riichiBonus
            
            for index in players.indices where index != winnerIndex {
                players[index].score -= paymentPerPlayer
                totalGain += paymentPerPlayer
            }
            
            players[winnerIndex].score += totalGain
        }
        
        riichiStickCount = 0
        advanceRoundAfterWin(winnerIndex: winnerIndex)
        clearRiichiState()
        return dealerChanged
    }

    func settleMultipleRon(settlements: [QuickRonSettlement], loserIndex: Int) -> Bool {
        guard !isMatchFinished else { return false }
        guard players.indices.contains(loserIndex) else { return false }
        guard !settlements.isEmpty else { return false }
        
        let validSettlements = settlements.filter {
            players.indices.contains($0.winnerIndex) && $0.winnerIndex != loserIndex && $0.points > 0
        }
        guard !validSettlements.isEmpty else { return false }
        
        let orderedWinnerIndices = multipleRonRule.orderedWinnerIndices(
            loserIndex: loserIndex,
            winnerIndices: validSettlements.map(\.winnerIndex),
            playerCount: players.count
        )
        let anyEastWinner = validSettlements.contains { isEastPlayer($0.winnerIndex) }
        let dealerChanged = !anyEastWinner
        let riichiBonus = riichiStickCount * 1000
        let honbaBonus = honbaCount * 300
        
        for settlement in validSettlements {
            let isHeadWinner = orderedWinnerIndices.first == settlement.winnerIndex
            let extraGain = isHeadWinner ? (riichiBonus + honbaBonus) : 0
            players[settlement.winnerIndex].score += settlement.points + extraGain
        }
        
        players[loserIndex].score -= validSettlements.reduce(0) { $0 + $1.points } + honbaBonus
        
        riichiStickCount = 0
        advanceRoundAfterRonWinners(anyEastWinner: anyEastWinner)
        clearRiichiState()
        return dealerChanged
    }

    func calculateFormalScore(
        winnerIndex: Int,
        loserIndex: Int?,
        winType: WinType,
        han: Int,
        fu: Int,
        yakumanMultiplier: Int = 0
    ) -> FormalScoreResult? {
        guard !isMatchFinished else { return nil }
        guard players.indices.contains(winnerIndex) else { return nil }
        guard han > 0 else { return nil }
        guard yakumanMultiplier > 0 || han >= 13 || fu > 0 else { return nil }
        
        let eastWin = isEastPlayer(winnerIndex)
        let basePoints = basicPoints(han: han, fu: fu, yakumanMultiplier: yakumanMultiplier)
        let honbaBonus = honbaCount * 100
        let riichiBonus = riichiStickCount * 1000
        let limitName = scoreLimitName(han: han, fu: fu, yakumanMultiplier: yakumanMultiplier)
        
        switch winType {
        case .ron:
            guard let loserIndex, players.indices.contains(loserIndex), loserIndex != winnerIndex else {
                return nil
            }
            
            let ronValue = roundedUpToHundred(basePoints * (eastWin ? 6 : 4))
            let totalPayment = ronValue + honbaCount * 300
            
            return FormalScoreResult(
                winnerIndex: winnerIndex,
                loserIndex: loserIndex,
                winType: winType,
                isEastWin: eastWin,
                han: han,
                fu: fu,
                honbaCount: honbaCount,
                riichiStickCount: riichiStickCount,
                winnerGain: totalPayment + riichiBonus,
                loserPayment: totalPayment,
                dealerPayment: nil,
                nonDealerPayment: nil,
                yakumanMultiplier: yakumanMultiplier,
                limitName: limitName
            )
            
        case .tsumo:
            if eastWin {
                let payment = roundedUpToHundred(basePoints * 2) + honbaBonus
                return FormalScoreResult(
                    winnerIndex: winnerIndex,
                    loserIndex: nil,
                    winType: winType,
                    isEastWin: true,
                    han: han,
                    fu: fu,
                    honbaCount: honbaCount,
                    riichiStickCount: riichiStickCount,
                    winnerGain: payment * 3 + riichiBonus,
                    loserPayment: nil,
                    dealerPayment: nil,
                    nonDealerPayment: payment,
                    yakumanMultiplier: yakumanMultiplier,
                    limitName: limitName
                )
            } else {
                let dealerPayment = roundedUpToHundred(basePoints * 2) + honbaBonus
                let nonDealerPayment = roundedUpToHundred(basePoints) + honbaBonus
                return FormalScoreResult(
                    winnerIndex: winnerIndex,
                    loserIndex: nil,
                    winType: winType,
                    isEastWin: false,
                    han: han,
                    fu: fu,
                    honbaCount: honbaCount,
                    riichiStickCount: riichiStickCount,
                    winnerGain: dealerPayment + nonDealerPayment * 2 + riichiBonus,
                    loserPayment: nil,
                    dealerPayment: dealerPayment,
                    nonDealerPayment: nonDealerPayment,
                    yakumanMultiplier: yakumanMultiplier,
                    limitName: limitName
                )
            }
        }
    }
    
    func settleFormalScore(
        winnerIndex: Int,
        loserIndex: Int?,
        winType: WinType,
        han: Int,
        fu: Int,
        yakumanMultiplier: Int = 0
    ) -> Bool {
        let dealerChanged = !isEastPlayer(winnerIndex)
        guard let result = calculateFormalScore(
            winnerIndex: winnerIndex,
            loserIndex: loserIndex,
            winType: winType,
            han: han,
            fu: fu,
            yakumanMultiplier: yakumanMultiplier
        ) else {
            return false
        }
        
        switch result.winType {
        case .ron:
            guard let loserIndex = result.loserIndex,
                  let payment = result.loserPayment else { return false }
            players[winnerIndex].score += result.winnerGain
            players[loserIndex].score -= payment
            
        case .tsumo:
            for index in players.indices where index != winnerIndex {
                if isEastPlayer(index) {
                    if let dealerPayment = result.dealerPayment {
                        players[index].score -= dealerPayment
                    }
                } else if let nonDealerPayment = result.nonDealerPayment {
                    players[index].score -= nonDealerPayment
                }
            }
            players[winnerIndex].score += result.winnerGain
        }
        
        riichiStickCount = 0
        advanceRoundAfterWin(winnerIndex: winnerIndex)
        clearRiichiState()
        return dealerChanged
    }

    func calculateMultipleFormalRon(
        losersIndex: Int,
        winnerInputs: [(winnerIndex: Int, han: Int, fu: Int, yakumanMultiplier: Int)]
    ) -> [FormalScoreResult] {
        guard !isMatchFinished else { return [] }
        guard players.indices.contains(losersIndex) else { return [] }

        let orderedWinnerIndices = multipleRonRule.orderedWinnerIndices(
            loserIndex: losersIndex,
            winnerIndices: winnerInputs.map(\.winnerIndex),
            playerCount: players.count
        )

        let rawResults = winnerInputs.compactMap { input in
            calculateFormalScore(
                winnerIndex: input.winnerIndex,
                loserIndex: losersIndex,
                winType: .ron,
                han: input.han,
                fu: input.fu,
                yakumanMultiplier: input.yakumanMultiplier
            )
        }

        return orderedWinnerIndices.compactMap { winnerIndex in
            guard var result = rawResults.first(where: { $0.winnerIndex == winnerIndex }) else {
                return nil
            }

            let isHeadWinner = orderedWinnerIndices.first == winnerIndex
            if !isHeadWinner {
                let honbaBonus = result.honbaCount * 300
                result.winnerGain -= honbaBonus + result.riichiBonus
                result.loserPayment = (result.loserPayment ?? 0) - honbaBonus
                result.honbaCount = 0
                result.riichiStickCount = 0
            }
            return result
        }
    }
    
    func settleMultipleFormalRon(
        loserIndex: Int,
        winnerInputs: [(winnerIndex: Int, han: Int, fu: Int, yakumanMultiplier: Int)]
    ) -> Bool {
        let results = calculateMultipleFormalRon(
            losersIndex: loserIndex,
            winnerInputs: winnerInputs
        )
        guard !results.isEmpty else { return false }
        
        let anyEastWinner = results.contains { $0.isEastWin }
        let dealerChanged = !anyEastWinner
        let totalPayment = results.reduce(0) { $0 + ($1.loserPayment ?? 0) }
        
        for result in results {
            players[result.winnerIndex].score += result.winnerGain
        }
        
        players[loserIndex].score -= totalPayment
        riichiStickCount = 0
        advanceRoundAfterRonWinners(anyEastWinner: anyEastWinner)
        clearRiichiState()
        return dealerChanged
    }
    
    func registerDraw(eastIsTenpai: Bool) -> Bool {
        guard !isMatchFinished else { return false }
        let dealerChanged = !eastIsTenpai
        
        if eastIsTenpai {
            honbaCount += 1
        } else {
            honbaCount = 0
            advanceRound()
        }
        
        clearRiichiState()
        return dealerChanged
    }
    
    func resetGame(nicknames: [String]? = nil) {
        players = initialPlayers
        let appliedNicknames = nicknames ?? lastEnteredNicknames
        
        if appliedNicknames.count == players.count {
            for index in players.indices {
                let trimmedName = appliedNicknames[index].trimmingCharacters(in: .whitespacesAndNewlines)
                players[index].nickname = trimmedName.isEmpty ? players[index].position : trimmedName
            }
            lastEnteredNicknames = appliedNicknames
        }
        
        roundWindIndex = 0
        roundNumber = 1
        honbaCount = 0
        riichiStickCount = 0
        lastWinType = .ron
        lastPointInput = defaultPointInput
        isMatchFinished = false
    }
    
    private func advanceRoundAfterWin(winnerIndex: Int) {
        if isEastPlayer(winnerIndex) {
            honbaCount += 1
            return
        }
        
        honbaCount = 0
        advanceRound()
    }

    private func advanceRoundAfterRonWinners(anyEastWinner: Bool) {
        if anyEastWinner {
            honbaCount += 1
            return
        }
        
        honbaCount = 0
        advanceRound()
    }
    
    private func advanceRound() {
        rotateDealerCounterclockwise()
        
        if roundNumber < 4 {
            roundNumber += 1
            return
        }
        
        if roundWindIndex < roundWinds.count - 1 {
            roundWindIndex += 1
            roundNumber = 1
            return
        }
        
        isMatchFinished = true
    }
    
    private func rotateDealerCounterclockwise() {
        let currentNames = players.map(\.name)
        
        for index in players.indices {
            let previousIndex = (index - 1 + players.count) % players.count
            players[index].name = currentNames[previousIndex]
        }
    }
    
    private func basicPoints(han: Int, fu: Int, yakumanMultiplier: Int) -> Int {
        if yakumanMultiplier > 0 { return 8000 * yakumanMultiplier }
        if han >= 13 { return 8000 }
        if han >= 11 { return 6000 }
        if han >= 8 { return 4000 }
        if han >= 6 { return 3000 }
        
        let calculatedBase = fu * Int(pow(2.0, Double(han + 2)))
        if han >= 5 || calculatedBase >= 2000 {
            return 2000
        }
        
        return calculatedBase
    }
    
    private func scoreLimitName(han: Int, fu: Int, yakumanMultiplier: Int) -> String? {
        if yakumanMultiplier >= 2 { return "双役满" }
        if yakumanMultiplier == 1 || han >= 13 { return "役满" }
        if han >= 11 { return "三倍满" }
        if han >= 8 { return "倍满" }
        if han >= 6 { return "跳满" }
        let calculatedBase = fu * Int(pow(2.0, Double(han + 2)))
        if han >= 5 || calculatedBase >= 2000 { return "满贯" }
        return nil
    }
    
    private func roundedUpToHundred(_ value: Int) -> Int {
        ((value + 99) / 100) * 100
    }
}
