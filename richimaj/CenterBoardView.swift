//
//  CenterBoardView.swift
//  richimaj
//
//  Created by Codex on 2026/4/1.
//

import SwiftUI

struct CenterBoardView: View {
    @ObservedObject var game: GameState
    var compactLayout = false
    var rotationDegrees: Double = 0
    
    var body: some View {
        VStack(spacing: 8) {
            Text(game.roundText)
                .font(compactLayout ? .subheadline : .headline)
                .bold()
            
            Text("\(game.honbaCount) 本场")
                .font(compactLayout ? .caption2 : .caption)
                .bold()
            
            Text("\(game.riichiStickCount) 立直棒")
                .font(compactLayout ? .caption2 : .caption)
                .bold()
        }
        .frame(width: compactLayout ? 98 : 120, height: compactLayout ? 96 : 116)
        .background(Color.brown.opacity(0.15))
        .cornerRadius(20)
        .rotationEffect(.degrees(rotationDegrees))
    }
}
