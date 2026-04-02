//
//  PlayerCardView.swift
//  richimaj
//
//  Created by Codex on 2026/4/1.
//

import SwiftUI

struct CompetitiveTimerDisplay {
    var mainTime: Int
    var reserveTime: Int
}

struct PlayerCardView: View {
    let player: PlayerScore
    let onRiichi: () -> Void
    var canRiichi = true
    var compactLayout = false
    var timerDisplay: CompetitiveTimerDisplay? = nil
    var showCompetitiveChrome = false
    var leftActionTitle: String? = nil
    var onLeftAction: (() -> Void)? = nil
    var showStartButton = false
    var onStartTurn: (() -> Void)? = nil
    var showFinishButton = false
    var onFinishTurn: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: compactLayout ? 10 : 12) {
            if showCompetitiveChrome {
                leftAssistantArea
            } else if let timerDisplay {
                timerPanel(timerDisplay)
            }
            
            VStack(spacing: 5) {
                seatText
                    .padding(.top, 10)
                
                Text("\(player.score)")
                    .font(.title3)
                    .bold()
                
                Text(player.nickname)
                    .font(.caption)
                    .foregroundColor(.gray)
                
                riichiStick(isVisible: player.isRiichi)
                
                Button(player.isRiichi ? "已立直" : "立直") {
                    onRiichi()
                }
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, compactLayout ? 6 : 8)
                .padding(.vertical, 2)
                .background(player.isRiichi ? Color.gray.opacity(0.18) : Color.blue.opacity(0.15))
                .cornerRadius(8)
                .disabled(player.isRiichi || player.score < 1000 || !canRiichi)
                .frame(height: compactLayout ? 18 : 20)
            }
            .frame(width: cardWidth, height: cardHeight)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(radius: 3)
            
            if showCompetitiveChrome {
                competitiveActionButton
            } else if let onFinishTurn {
                finishButton(action: onFinishTurn)
            }
        }
        .offset(x: showCompetitiveChrome ? competitiveCenterOffset : 0)
    }
    
    @ViewBuilder
    var seatText: some View {
        switch player.name {
        case "东家":
            Text("東")
                .font(compactLayout ? .title3 : .title2)
                .fontWeight(.black)
                .foregroundColor(.red)
        case "南家":
            Text("南")
                .font(compactLayout ? .headline : .title3)
                .bold()
        case "西家":
            Text("西")
                .font(compactLayout ? .headline : .title3)
                .bold()
        case "北家":
            Text("北")
                .font(compactLayout ? .headline : .title3)
                .bold()
        default:
            Text(player.name)
                .font(compactLayout ? .headline : .title3)
                .bold()
        }
    }
    
    var cardWidth: CGFloat { compactLayout ? 102 : 118 }
    var cardHeight: CGFloat { compactLayout ? 104 : 116 }
    var leftAssistantWidth: CGFloat { compactLayout ? 112 : 128 }
    var timerPanelWidth: CGFloat { leftAssistantWidth * 0.66 }
    var leftActionWidth: CGFloat { leftAssistantWidth * 0.34 }
    var assistantHeight: CGFloat { compactLayout ? 50 : 56 }
    var actionButtonSize: CGFloat { compactLayout ? 44 : 50 }
    var actionButtonFrame: CGFloat { compactLayout ? 48 : 56 }
    var competitiveCenterOffset: CGFloat { -(leftAssistantWidth - actionButtonFrame) / 2 }

    @ViewBuilder
    var leftAssistantArea: some View {
        HStack(spacing: 4) {
            if let timerDisplay {
                timerPanel(timerDisplay)
            } else {
                Color.clear
                    .frame(width: timerPanelWidth, height: assistantHeight)
            }
            
            if let leftActionTitle, let onLeftAction {
                leftActionButton(title: leftActionTitle, action: onLeftAction)
            } else {
                Color.clear
                    .frame(width: leftActionWidth, height: assistantHeight)
            }
        }
        .frame(width: leftAssistantWidth)
    }
    
    func timerPanel(_ timerDisplay: CompetitiveTimerDisplay) -> some View {
        HStack(spacing: 4) {
            timerRow(title: "保留", value: timerDisplay.reserveTime, emphasizeValue: false)
            timerRow(title: "", value: timerDisplay.mainTime, emphasizeValue: true)
        }
        .frame(width: timerPanelWidth)
    }
    
    func timerRow(title: String, value: Int, emphasizeValue: Bool) -> some View {
        VStack(spacing: 2) {
            if !title.isEmpty {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text("\(max(value, 0))")
                .font(emphasizeValue ? (compactLayout ? .title3 : .title2) : .headline)
                .monospacedDigit()
                .bold()
        }
        .frame(maxWidth: .infinity)
        .frame(height: assistantHeight)
        .background(Color.white.opacity(0.9))
        .cornerRadius(10)
        .shadow(radius: 1)
    }

    func leftActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            RoundedRectangle(cornerRadius: 12)
                .fill(title == "自摸" ? Color.green.opacity(0.9) : Color.orange.opacity(0.9))
                .frame(width: leftActionWidth, height: assistantHeight)
                .overlay {
                    Text(title)
                        .font(compactLayout ? .subheadline : .headline)
                        .foregroundColor(.white)
                        .bold()
                        .minimumScaleFactor(0.7)
                }
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    var competitiveActionButton: some View {
        if showStartButton, let onStartTurn {
            Circle()
                .fill(Color.clear)
                .frame(width: actionButtonFrame, height: actionButtonFrame)
                .overlay {
                    Button {
                        onStartTurn()
                    } label: {
                        Circle()
                            .fill(Color.green)
                            .frame(width: actionButtonSize, height: actionButtonSize)
                            .overlay {
                                Image(systemName: "play.fill")
                                    .font(compactLayout ? .subheadline : .headline)
                                    .foregroundColor(.white)
                                    .padding(.leading, 2)
                            }
                    }
                    .buttonStyle(.plain)
                }
        } else if showFinishButton, let onFinishTurn {
            finishButton(action: onFinishTurn)
        } else {
            Color.clear
                .frame(width: actionButtonFrame, height: actionButtonFrame)
        }
    }
    
    func finishButton(action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Circle()
                .fill(Color.red)
                .frame(width: actionButtonSize, height: actionButtonSize)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(compactLayout ? .subheadline : .headline)
                        .foregroundColor(.white)
                }
        }
        .buttonStyle(.plain)
        .frame(width: actionButtonFrame, height: actionButtonFrame)
    }
    
    @ViewBuilder
    func riichiStick(isVisible: Bool) -> some View {
        if isVisible {
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.98, green: 0.98, blue: 0.96), Color(red: 0.82, green: 0.82, blue: 0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 56, height: 11)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        .padding(.bottom, 6)
                }
                .overlay {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                        .shadow(color: .red.opacity(0.3), radius: 1, y: 0.5)
                }
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
        } else {
            Color.clear
                .frame(width: 56, height: 11)
        }
    }
}
