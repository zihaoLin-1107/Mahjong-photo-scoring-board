//
//  MultipleRonRule.swift
//  richimaj
//
//  Created by Codex on 2026/4/3.
//

import Foundation

enum RiichiStickDistributionRule {
    case allToHeadWinner
}

enum HonbaDistributionRule {
    case allToHeadWinner
}

struct MultipleRonRule {
    var riichiStickDistribution: RiichiStickDistributionRule
    var honbaDistribution: HonbaDistributionRule

    static let commonOnlinePlatform = MultipleRonRule(
        riichiStickDistribution: .allToHeadWinner,
        honbaDistribution: .allToHeadWinner
    )

    func orderedWinnerIndices(loserIndex: Int, winnerIndices: [Int], playerCount: Int) -> [Int] {
        winnerIndices.sorted {
            turnDistance(from: loserIndex, to: $0, playerCount: playerCount)
                < turnDistance(from: loserIndex, to: $1, playerCount: playerCount)
        }
    }

    func isHeadWinner(_ winnerIndex: Int, loserIndex: Int, winnerIndices: [Int], playerCount: Int) -> Bool {
        orderedWinnerIndices(
            loserIndex: loserIndex,
            winnerIndices: winnerIndices,
            playerCount: playerCount
        ).first == winnerIndex
    }

    private func turnDistance(from loserIndex: Int, to winnerIndex: Int, playerCount: Int) -> Int {
        (winnerIndex - loserIndex + playerCount) % playerCount
    }
}
