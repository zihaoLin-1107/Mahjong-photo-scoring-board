//
//  ContentView.swift
//  richimaj
//
//  Created by linzihao on 2026/3/31.
//

import SwiftUI
import Combine
import UIKit

struct PatternDetectionResult {
    var han: Int
    var fu: Int
    var yakuNames: [String]
    var notes: [String]
    var yakumanMultiplier: Int = 0
}

enum TileInputSection: String, CaseIterable, Identifiable {
    case concealed = "手牌"
    case openMeld = "副露"
    case winning = "胡牌"
    
    var id: String { rawValue }
}

enum CircumstantialYaku: String, CaseIterable, Hashable, Identifiable {
    case ippatsu = "一发"
    case haitei = "海底捞月"
    case houtei = "河底捞鱼"
    case rinshan = "岭上开花"
    case chankan = "抢杠"

    var id: String { rawValue }
}

enum RiichiYakuKind: String, CaseIterable, Hashable {
    case none
    case riichi = "立直"
    case doubleRiichi = "双立直"

    var yakuName: String? {
        switch self {
        case .none: return nil
        case .riichi: return "立直"
        case .doubleRiichi: return "双立直"
        }
    }

    var hanValue: Int {
        switch self {
        case .none: return 0
        case .riichi: return 1
        case .doubleRiichi: return 2
        }
    }
}

enum MahjongTile: Int, CaseIterable, Identifiable, Hashable {
    case man1, man2, man3, man4, man5, man6, man7, man8, man9
    case pin1, pin2, pin3, pin4, pin5, pin6, pin7, pin8, pin9
    case sou1, sou2, sou3, sou4, sou5, sou6, sou7, sou8, sou9
    case east, south, west, north, white, green, red
    
    var id: Int { rawValue }
    
    var label: String {
        switch self {
        case .man1: return "1万"
        case .man2: return "2万"
        case .man3: return "3万"
        case .man4: return "4万"
        case .man5: return "5万"
        case .man6: return "6万"
        case .man7: return "7万"
        case .man8: return "8万"
        case .man9: return "9万"
        case .pin1: return "1筒"
        case .pin2: return "2筒"
        case .pin3: return "3筒"
        case .pin4: return "4筒"
        case .pin5: return "5筒"
        case .pin6: return "6筒"
        case .pin7: return "7筒"
        case .pin8: return "8筒"
        case .pin9: return "9筒"
        case .sou1: return "1索"
        case .sou2: return "2索"
        case .sou3: return "3索"
        case .sou4: return "4索"
        case .sou5: return "5索"
        case .sou6: return "6索"
        case .sou7: return "7索"
        case .sou8: return "8索"
        case .sou9: return "9索"
        case .east: return "东"
        case .south: return "南"
        case .west: return "西"
        case .north: return "北"
        case .white: return "白"
        case .green: return "发"
        case .red: return "中"
        }
    }
    
    var suitTitle: String {
        switch self {
        case .man1, .man2, .man3, .man4, .man5, .man6, .man7, .man8, .man9:
            return "万"
        case .pin1, .pin2, .pin3, .pin4, .pin5, .pin6, .pin7, .pin8, .pin9:
            return "饼"
        case .sou1, .sou2, .sou3, .sou4, .sou5, .sou6, .sou7, .sou8, .sou9:
            return "条"
        default:
            return "字"
        }
    }
    
    var isHonor: Bool {
        rawValue >= 27
    }
    
    var isTerminal: Bool {
        guard !isHonor else { return false }
        let number = rawValue % 9 + 1
        return number == 1 || number == 9
    }
    
    var isTerminalOrHonor: Bool {
        isHonor || isTerminal
    }
    
    var suitIndex: Int? {
        if rawValue < 27 {
            return rawValue / 9
        }
        return nil
    }
    
    var number: Int? {
        guard !isHonor else { return nil }
        return rawValue % 9 + 1
    }
    
    static var groupedTiles: [[MahjongTile]] {
        [
            Array(allCases[0...8]),
            Array(allCases[9...17]),
            Array(allCases[18...26]),
            Array(allCases[27...33])
        ]
    }
}

enum HandGroupKind {
    case sequence
    case triplet
}

struct HandGroup {
    var kind: HandGroupKind
    var tiles: [Int]
}

enum WaitKind {
    case ryanmen
    case kanchan
    case penchan
    case tanki
    case shanpon
}

struct StandardHandCandidate {
    var pairTile: Int
    var groups: [HandGroup]
    var waitKind: WaitKind
}

struct HandAnalysisContext {
    var openMeldGroups: [OpenMeldGroup]
    
    var openHandGroups: [HandGroup] {
        openMeldGroups.compactMap(\.handGroup)
    }
    
    var openTripletLikeCount: Int {
        openHandGroups.filter { $0.kind == .triplet }.count
    }
    
    var openSequenceCount: Int {
        openHandGroups.filter { $0.kind == .sequence }.count
    }
}

enum AppMode: String {
    case casual = "休闲模式"
    case competitive = "竞技模式"
}

struct CompetitiveConfig: Equatable {
    var turnTime: Int
    var reserveTime: Int
}

struct PendingCallWindow: Equatable {
    var sourcePlayerIndex: Int
    var claimantIndex: Int
    var remainingSeconds: Int
}

struct FormalScoringDraft: Identifiable, Hashable {
    let id = UUID()
    var winnerIndex: Int
    var winType: WinType
    var loserIndex: Int?
    var riichiYaku: RiichiYakuKind = .none
    var hasIppatsu = false
}

struct FormalWinnerEntry: Identifiable {
    let id = UUID()
    var winnerIndex: Int
    var hanInput: String
    var fuInput: String
    var yakumanMultiplier: Int = 0
    var detectedText: String = ""
    var riichiYaku: RiichiYakuKind = .none
    var hasIppatsu = false
}

struct HandPatternDraft {
    var activeSection: TileInputSection = .concealed
    var handCounts: [MahjongTile: Int] = [:]
    var openCounts: [MahjongTile: Int] = [:]
    var openMeldGroups: [OpenMeldGroup] = []
    var concealedKanTiles: Set<MahjongTile> = []
    var riichiYaku: RiichiYakuKind = .none
    var selectedCircumstantialYaku: Set<CircumstantialYaku> = []
    var winningTile: MahjongTile? = nil
    var doraCount: Int = 0
    var redDoraCount: Int = 0
    var analysisResult: PatternDetectionResult? = nil
}

enum PatternInputEntryMode {
    case manual
    case photoAssisted
}

enum OpenMeldType: String, CaseIterable, Identifiable {
    case chi = "吃"
    case pon = "碰"
    case openKan = "明杠"
    case concealedKan = "暗杠"
    
    var id: String { rawValue }
}

struct OpenMeldGroup: Identifiable, Equatable {
    let id = UUID()
    var type: OpenMeldType
    var tiles: [MahjongTile]
}

extension OpenMeldGroup {
    var structuralTiles: [Int] {
        switch type {
        case .chi:
            return tiles.map(\.rawValue)
        case .pon, .openKan, .concealedKan:
            guard let first = tiles.first else { return [] }
            return [first.rawValue, first.rawValue, first.rawValue]
        }
    }
    
    var handGroup: HandGroup? {
        switch type {
        case .chi:
            return HandGroup(kind: .sequence, tiles: structuralTiles)
        case .pon, .openKan, .concealedKan:
            return HandGroup(kind: .triplet, tiles: structuralTiles)
        }
    }
}

struct ContentView: View {
    @State private var goToCasualMode = false
    @State private var goToCompetitiveSetup = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.93, green: 0.88, blue: 0.72)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Text("立直麻将记分")
                        .font(.largeTitle)
                        .bold()
                    
                    Text("请选择开始模式")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Button {
                        goToCasualMode = true
                    } label: {
                        modeCard(
                            title: "休闲模式",
                            subtitle: "快速开始，直接进入记分板"
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        goToCompetitiveSetup = true
                    } label: {
                        modeCard(
                            title: "竞技模式",
                            subtitle: "先设置单次思考时间和保留时间"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
            }
            .navigationDestination(isPresented: $goToCasualMode) {
                ScoreboardView(mode: .casual)
            }
            .navigationDestination(isPresented: $goToCompetitiveSetup) {
                CompetitiveSetupView()
            }
        }
    }
    
    func modeCard(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3)
                .bold()
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.88))
        .cornerRadius(18)
        .shadow(radius: 3)
        .contentShape(Rectangle())
    }
}

struct ScoreboardView: View {
    let mode: AppMode
    var competitiveConfig: CompetitiveConfig? = nil
    
    @StateObject private var game = GameState()
    @State private var showingNewGameSetup = false
    @State private var showingDrawDecision = false
    @State private var activeTurnIndex = 0
    @State private var currentTurnMainTime = 0
    @State private var reserveTimes = [0, 0, 0, 0]
    @State private var hasInitializedCompetitiveState = false
    @State private var handTimerStarted = false
    @State private var formalScoringDraft: FormalScoringDraft? = nil
    @State private var pendingCallWindow: PendingCallWindow? = nil
    @State private var completedTurnsInCurrentHand = [0, 0, 0, 0]
    @State private var callOccurredInCurrentHand = false
    @State private var riichiYakuByPlayer = Array(repeating: RiichiYakuKind.none, count: 4)
    @State private var riichiDeclarationCompletedTurns: [Int?] = Array(repeating: nil, count: 4)
    @State private var ippatsuEligiblePlayers: Set<Int> = []
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            let compactLayout = geometry.size.width < 390
            let largeScreenLayout = geometry.size.width >= 700
            let horizontalPadding: CGFloat = compactLayout ? 8 : 12
            let verticalPadding: CGFloat = compactLayout ? 12 : 16
            let boardSafetyInset: CGFloat = compactLayout ? 14 : 20
            let controlsVerticalSpacing: CGFloat = compactLayout ? 8 : 12
            let boardToControlsSpacing: CGFloat = compactLayout ? 16 : 24
            let controlsHeight: CGFloat = controlsSectionHeight(
                width: geometry.size.width - horizontalPadding * 2,
                compactLayout: compactLayout
            )
            let cardWidth: CGFloat = compactLayout ? 102 : 118
            let cardHeight: CGFloat = compactLayout ? 104 : 116
            let leftAssistantWidth: CGFloat = compactLayout ? 112 : 128
            let actionButtonFrame: CGFloat = compactLayout ? 48 : 56
            let centerBoardWidth: CGFloat = compactLayout ? 98 : 120
            let centerBoardHeight: CGFloat = compactLayout ? 96 : 116
            let horizontalGap: CGFloat = compactLayout ? 6 : 10
            let verticalGap: CGFloat = compactLayout ? 10 : 14
            let competitiveClearance: CGFloat = isCompetitiveMode ? (compactLayout ? 12 : 16) : 0
            let chromeSpacing: CGFloat = 16
            let playerContentWidth = isCompetitiveMode
                ? leftAssistantWidth + cardWidth + actionButtonFrame + chromeSpacing
                : cardWidth
            let sideSlotWidth = cardHeight
            let sideSlotHeight = playerContentWidth
            let boardAreaWidth = sideSlotWidth * 2 + centerBoardWidth + horizontalGap * 2
            let boardAreaHeight = cardHeight * 2 + centerBoardHeight + verticalGap * 2
            let topBottomOffset = centerBoardHeight / 2 + cardHeight / 2 + verticalGap + competitiveClearance
            let sideOffset = centerBoardWidth / 2 + sideSlotWidth / 2 + horizontalGap + competitiveClearance
            let availableBoardWidth = geometry.size.width - horizontalPadding * 2 - boardSafetyInset * 2
            let availableBoardHeight = geometry.size.height
                - verticalPadding * 2
                - controlsHeight
                - controlsVerticalSpacing
                - boardToControlsSpacing
                - boardSafetyInset * 2
            let widthScale = availableBoardWidth / boardAreaWidth
            let heightScale = availableBoardHeight / boardAreaHeight
            let maxBoardScale: CGFloat = largeScreenLayout ? 1.9 : 1
            let boardScale = min(maxBoardScale, max(0.78, min(widthScale, heightScale)))
            
            ZStack {
                Color(red: 0.93, green: 0.88, blue: 0.72)
                    .ignoresSafeArea()
                
                VStack(spacing: boardToControlsSpacing) {
                    ZStack {
                        topPlayer(compactLayout: compactLayout)
                            .frame(width: playerContentWidth, height: cardHeight)
                            .offset(y: -topBottomOffset)
                        
                        leftPlayer(compactLayout: compactLayout)
                            .frame(width: sideSlotWidth, height: sideSlotHeight)
                            .offset(x: -sideOffset)
                        
                        CenterBoardView(
                            game: game,
                            compactLayout: compactLayout,
                            rotationDegrees: centerBoardRotation
                        )
                        
                        rightPlayer(compactLayout: compactLayout)
                            .frame(width: sideSlotWidth, height: sideSlotHeight)
                            .offset(x: sideOffset)
                        
                        bottomPlayer(compactLayout: compactLayout)
                            .frame(width: playerContentWidth, height: cardHeight)
                            .offset(y: topBottomOffset)
                    }
                    .frame(width: boardAreaWidth, height: boardAreaHeight)
                    .scaleEffect(boardScale)
                    .frame(width: boardAreaWidth * boardScale, height: boardAreaHeight * boardScale)
                    .padding(boardSafetyInset)
                    
                    controlsSection(compactLayout: compactLayout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
            }
        }
        .navigationTitle("立直麻将记分 · \(mode.rawValue)")
        .navigationDestination(item: $formalScoringDraft) { draft in
            FormalScoringView(game: game, draft: draft) {
                beginNextHand(dealerChanged: $0)
            }
        }
        .onAppear {
            if game.lastPointInput.isEmpty {
                game.lastPointInput = game.defaultPointInput
            }
            initializeCompetitionIfNeeded()
        }
        .sheet(isPresented: $showingNewGameSetup) {
            NewGameSetupView(game: game) {
                resetCompetitiveState()
            }
        }
            .confirmationDialog("东家是否听牌？", isPresented: $showingDrawDecision, titleVisibility: .visible) {
                Button("听牌，继续连庄") {
                    let dealerChanged = game.registerDraw(eastIsTenpai: true)
                    beginNextHand(dealerChanged: dealerChanged)
                }
                
                Button("未听牌，换庄") {
                    let dealerChanged = game.registerDraw(eastIsTenpai: false)
                    beginNextHand(dealerChanged: dealerChanged)
                }
            
            Button("取消", role: .cancel) {
            }
        } message: {
            Text("流局后本场会加 1。若东家未听牌，则换庄；立直棒保留到下次有人胡牌时再结算。")
        }
        .onReceive(timer) { _ in
            tickCompetitiveTimer()
        }
    }
    
    var isCompetitiveMode: Bool {
        mode == .competitive && competitiveConfig != nil
    }
    
    var eastPlayerIndex: Int {
        game.players.firstIndex(where: { $0.name == "东家" }) ?? 0
    }

    var centerBoardRotation: Double {
        switch eastPlayerIndex {
        case 1:
            return -90
        case 2:
            return 180
        case 3:
            return 90
        default:
            return 0
        }
    }
    
    func topPlayer(compactLayout: Bool) -> some View {
        playerView(for: 2, compactLayout: compactLayout)
            .rotationEffect(.degrees(180))
    }
    
    func leftPlayer(compactLayout: Bool) -> some View {
        playerView(for: 3, compactLayout: compactLayout)
            .rotationEffect(.degrees(90))
    }
    
    func rightPlayer(compactLayout: Bool) -> some View {
        playerView(for: 1, compactLayout: compactLayout)
            .rotationEffect(.degrees(-90))
    }
    
    func bottomPlayer(compactLayout: Bool) -> some View {
        playerView(for: 0, compactLayout: compactLayout)
    }
    
    func playerView(for index: Int, compactLayout: Bool) -> some View {
        PlayerCardView(
            player: game.players[index],
            onRiichi: {
                handleDeclareRiichi(for: index)
            },
            boardPosition: boardPosition(for: index),
            canRiichi: canDeclareRiichi(for: index),
            compactLayout: compactLayout,
            timerDisplay: timerDisplay(for: index),
            showCompetitiveChrome: isCompetitiveMode,
            leftActionTitle: leftActionTitle(for: index),
            onLeftAction: leftAction(for: index),
            callActionTitle: callActionTitle(for: index),
            onCallAction: callAction(for: index),
            showStartButton: isCompetitiveMode && activeTurnIndex == index && !handTimerStarted,
            onStartTurn: isCompetitiveMode && activeTurnIndex == index && !handTimerStarted ? {
                startTurnTimer()
            } : nil,
            showFinishButton: isCompetitiveMode && activeTurnIndex == index && handTimerStarted && pendingCallWindow == nil,
            onFinishTurn: isCompetitiveMode && activeTurnIndex == index && handTimerStarted ? {
                finishCurrentTurn()
            } : nil
        )
    }

    func boardPosition(for index: Int) -> BoardSeatPosition {
        switch index {
        case 0:
            return .bottom
        case 1:
            return .right
        case 2:
            return .top
        default:
            return .left
        }
    }

    func canDeclareRiichi(for index: Int) -> Bool {
        if !isCompetitiveMode {
            return true
        }
        return activeTurnIndex == index && handTimerStarted
    }

    @ViewBuilder
    func controlsSection(compactLayout: Bool) -> some View {
        if isCompetitiveMode {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: compactLayout ? 8 : 12) {
                    drawButton(compactLayout: compactLayout)
                    resetButton(compactLayout: compactLayout)
                }
                
                VStack(spacing: compactLayout ? 8 : 12) {
                    drawButton(compactLayout: compactLayout)
                    resetButton(compactLayout: compactLayout)
                }
            }
        } else if compactLayout {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    quickSettlementLink(compactLayout: compactLayout)
                    formalScoringLink(compactLayout: compactLayout)
                }
                HStack(spacing: 8) {
                    drawButton(compactLayout: compactLayout)
                    resetButton(compactLayout: compactLayout)
                }
            }
        } else {
            HStack(spacing: 12) {
                quickSettlementLink(compactLayout: compactLayout)
                formalScoringLink(compactLayout: compactLayout)
                drawButton(compactLayout: compactLayout)
                resetButton(compactLayout: compactLayout)
            }
        }
    }

    func quickSettlementLink(compactLayout: Bool) -> some View {
        NavigationLink("快捷结算") {
            QuickSettlementView(game: game) {
                beginNextHand(dealerChanged: $0)
            }
        }
        .font(compactLayout ? .subheadline : .headline)
        .padding(.horizontal, compactLayout ? 16 : 20)
        .padding(.vertical, 10)
        .background(Color.blue.opacity(0.18))
        .cornerRadius(10)
    }

    func formalScoringLink(compactLayout: Bool) -> some View {
        NavigationLink("正式算分") {
            FormalScoringView(game: game) {
                beginNextHand(dealerChanged: $0)
            }
        }
        .font(compactLayout ? .subheadline : .headline)
        .padding(.horizontal, compactLayout ? 16 : 20)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.16))
        .cornerRadius(10)
    }

    func drawButton(compactLayout: Bool) -> some View {
        Button("流局") {
            showingDrawDecision = true
        }
        .font(compactLayout ? .subheadline : .headline)
        .padding(.horizontal, compactLayout ? 22 : 20)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.2))
        .cornerRadius(10)
    }

    func resetButton(compactLayout: Bool) -> some View {
        Button("重新开局") {
            showingNewGameSetup = true
        }
        .font(compactLayout ? .subheadline : .headline)
        .padding(.horizontal, compactLayout ? 16 : 20)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.18))
        .cornerRadius(10)
    }

    func controlsSectionHeight(width: CGFloat, compactLayout: Bool) -> CGFloat {
        let buttonHeight: CGFloat = 40
        
        if isCompetitiveMode {
            let estimatedWidth: CGFloat = compactLayout ? 212 : 240
            let fitsInOneRow = width >= estimatedWidth
            return fitsInOneRow ? buttonHeight : buttonHeight * 2 + (compactLayout ? 8 : 12)
        }
        
        if compactLayout {
            return buttonHeight * 2 + 8
        }
        
        return buttonHeight
    }

    func leftActionTitle(for index: Int) -> String? {
        guard isCompetitiveMode, handTimerStarted else { return nil }
        if activeTurnIndex == index {
            return "自摸"
        }
        return "胡"
    }

    func leftAction(for index: Int) -> (() -> Void)? {
        guard isCompetitiveMode, handTimerStarted else { return nil }
        return {
            openFormalScoring(for: index)
        }
    }

    func callActionTitle(for index: Int) -> String? {
        guard canCall(for: index) else { return nil }
        return "鸣"
    }

    func callAction(for index: Int) -> (() -> Void)? {
        guard canCall(for: index) else { return nil }
        return {
            handleCall(for: index)
        }
    }
    
    func timerDisplay(for index: Int) -> CompetitiveTimerDisplay? {
        guard isCompetitiveMode, activeTurnIndex == index, handTimerStarted else { return nil }
        return CompetitiveTimerDisplay(
            mainTime: currentTurnMainTime,
            reserveTime: reserveTimes[index]
        )
    }
    
    func initializeCompetitionIfNeeded() {
        guard let competitiveConfig else { return }
        guard !hasInitializedCompetitiveState else { return }
        
        reserveTimes = Array(repeating: competitiveConfig.reserveTime, count: game.players.count)
        currentTurnMainTime = competitiveConfig.turnTime
        activeTurnIndex = eastPlayerIndex
        handTimerStarted = false
        hasInitializedCompetitiveState = true
    }
    
    func resetCompetitiveState() {
        guard let competitiveConfig else { return }
        reserveTimes = Array(repeating: competitiveConfig.reserveTime, count: game.players.count)
        currentTurnMainTime = competitiveConfig.turnTime
        activeTurnIndex = eastPlayerIndex
        handTimerStarted = false
        pendingCallWindow = nil
        completedTurnsInCurrentHand = Array(repeating: 0, count: game.players.count)
        callOccurredInCurrentHand = false
        riichiYakuByPlayer = Array(repeating: .none, count: game.players.count)
        riichiDeclarationCompletedTurns = Array(repeating: nil, count: game.players.count)
        ippatsuEligiblePlayers = []
        hasInitializedCompetitiveState = true
    }
    
    func beginNextHand(dealerChanged: Bool) {
        guard let competitiveConfig else { return }
        if dealerChanged {
            reserveTimes = Array(repeating: competitiveConfig.reserveTime, count: game.players.count)
        }
        activeTurnIndex = eastPlayerIndex
        currentTurnMainTime = competitiveConfig.turnTime
        handTimerStarted = false
        pendingCallWindow = nil
        completedTurnsInCurrentHand = Array(repeating: 0, count: game.players.count)
        callOccurredInCurrentHand = false
        riichiYakuByPlayer = Array(repeating: .none, count: game.players.count)
        riichiDeclarationCompletedTurns = Array(repeating: nil, count: game.players.count)
        ippatsuEligiblePlayers = []
    }
    
    func startTurnTimer() {
        guard competitiveConfig != nil else { return }
        handTimerStarted = true
        pendingCallWindow = nil
    }

    func handleDeclareRiichi(for index: Int) {
        guard canDeclareRiichi(for: index) else { return }
        guard game.players.indices.contains(index) else { return }
        guard !game.players[index].isRiichi else { return }

        let shouldBeDoubleRiichi =
            completedTurnsInCurrentHand[index] == 0
            && !callOccurredInCurrentHand

        game.declareRiichi(for: index)
        riichiYakuByPlayer[index] = shouldBeDoubleRiichi ? .doubleRiichi : .riichi
        riichiDeclarationCompletedTurns[index] = completedTurnsInCurrentHand[index]
        ippatsuEligiblePlayers.insert(index)
    }

    func openFormalScoring(for winnerIndex: Int) {
        guard isCompetitiveMode else { return }
        handTimerStarted = false
        pendingCallWindow = nil
        
        let draft: FormalScoringDraft
        if winnerIndex == activeTurnIndex {
            draft = FormalScoringDraft(
                winnerIndex: winnerIndex,
                winType: .tsumo,
                loserIndex: nil,
                riichiYaku: riichiYakuByPlayer[winnerIndex],
                hasIppatsu: ippatsuEligiblePlayers.contains(winnerIndex)
            )
        } else {
            draft = FormalScoringDraft(
                winnerIndex: winnerIndex,
                winType: .ron,
                loserIndex: activeTurnIndex,
                riichiYaku: riichiYakuByPlayer[winnerIndex],
                hasIppatsu: ippatsuEligiblePlayers.contains(winnerIndex)
            )
        }
        
        formalScoringDraft = draft
    }
    
    func finishCurrentTurn() {
        guard let competitiveConfig else { return }
        completedTurnsInCurrentHand[activeTurnIndex] += 1
        if let declaredAt = riichiDeclarationCompletedTurns[activeTurnIndex],
           completedTurnsInCurrentHand[activeTurnIndex] >= declaredAt + 2 {
            ippatsuEligiblePlayers.remove(activeTurnIndex)
        }
        activeTurnIndex = (activeTurnIndex + 1) % game.players.count
        currentTurnMainTime = competitiveConfig.turnTime
        handTimerStarted = true
        pendingCallWindow = nil
    }
    
    func tickCompetitiveTimer() {
        guard isCompetitiveMode else { return }
        guard !showingNewGameSetup, !showingDrawDecision else { return }
        guard !game.isMatchFinished else { return }
        guard handTimerStarted else { return }

        if var pendingCallWindow {
            pendingCallWindow.remainingSeconds -= 1
            if pendingCallWindow.remainingSeconds <= 0 {
                self.pendingCallWindow = nil
            } else {
                self.pendingCallWindow = pendingCallWindow
            }
        }
        
        if currentTurnMainTime > 0 {
            currentTurnMainTime -= 1
        } else if reserveTimes[activeTurnIndex] > 0 {
            reserveTimes[activeTurnIndex] -= 1
        }
    }

    func canCall(for index: Int) -> Bool {
        guard isCompetitiveMode, handTimerStarted else { return false }
        guard game.players.indices.contains(index) else { return false }

        if let pendingCallWindow {
            return index != pendingCallWindow.sourcePlayerIndex && index != pendingCallWindow.claimantIndex
        }

        return index != activeTurnIndex
    }

    func handleCall(for index: Int) {
        guard let competitiveConfig else { return }
        guard canCall(for: index) else { return }

        callOccurredInCurrentHand = true
        ippatsuEligiblePlayers.removeAll()

        if let pendingCallWindow {
            activeTurnIndex = index
            currentTurnMainTime = competitiveConfig.turnTime
            self.pendingCallWindow = nil
            handTimerStarted = true
            return
        }

        let sourcePlayerIndex = activeTurnIndex
        let nextPlayerIndex = (sourcePlayerIndex + 1) % game.players.count

        activeTurnIndex = index
        currentTurnMainTime = competitiveConfig.turnTime
        handTimerStarted = true

        if index == nextPlayerIndex {
            pendingCallWindow = PendingCallWindow(
                sourcePlayerIndex: sourcePlayerIndex,
                claimantIndex: index,
                remainingSeconds: 3
            )
        } else {
            pendingCallWindow = nil
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("ContentView Preview Disabled")
                    .font(.title3)
                    .bold()
                Text("完整 ContentView 依赖拍照识别与本地模型链。请直接运行模拟器或真机验证真实 UI。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
    }
}

struct CompetitiveSetupView: View {
    @State private var selectedTurnTime = 15
    @State private var selectedReserveTime = 30
    
    let turnTimeOptions = [10, 15, 20, 30, 45, 60]
    let reserveTimeOptions = [0, 10, 20, 30, 45, 60]
    
    var body: some View {
        Form {
            Section("竞技模式设置") {
                Picker("单次思考时间", selection: $selectedTurnTime) {
                    ForEach(turnTimeOptions, id: \.self) { seconds in
                        Text("\(seconds) 秒").tag(seconds)
                    }
                }
                
                Picker("保留时间", selection: $selectedReserveTime) {
                    ForEach(reserveTimeOptions, id: \.self) { seconds in
                        Text("\(seconds) 秒").tag(seconds)
                    }
                }
            }
            
            Section("说明") {
                Text("单次思考时间：每次轮到该玩家时都会重新拥有的时间。")
                Text("保留时间：单次时间用完后开始消耗，并且会累计减少。")
            }
            
            Section {
                NavigationLink("开始竞技模式") {
                    ScoreboardView(
                        mode: .competitive,
                        competitiveConfig: CompetitiveConfig(
                            turnTime: selectedTurnTime,
                            reserveTime: selectedReserveTime
                        )
                    )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("竞技设置")
    }
}

struct NewGameSetupView: View {
    @ObservedObject var game: GameState
    var onConfirm: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    
    @State private var eastName = ""
    @State private var southName = ""
    @State private var westName = ""
    @State private var northName = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("玩家昵称") {
                    TextField("东家", text: $eastName)
                    TextField("南家", text: $southName)
                    TextField("西家", text: $westName)
                    TextField("北家", text: $northName)
                }
                
                Section {
                    Button("确定") {
                        game.resetGame(
                            nicknames: [eastName, southName, westName, northName]
                        )
                        onConfirm?()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("重新开局")
            .onAppear {
                eastName = game.lastEnteredNicknames[0]
                southName = game.lastEnteredNicknames[1]
                westName = game.lastEnteredNicknames[2]
                northName = game.lastEnteredNicknames[3]
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct QuickSettlementView: View {
    @ObservedObject var game: GameState
    var onSettlementComplete: ((Bool) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    
    @State private var winnerIndex = 0
    @State private var ronWinnerIndices: [Int] = [0]
    @State private var ronPointValues: [Int: String] = [:]
    @State private var winType: WinType
    @State private var loserIndex = 1
    @State private var pointInput: String
    
    private let eastQuickPointOptions = ["1500", "2900", "3900", "4800", "5800", "7700", "9600", "12000"]
    private let nonEastQuickPointOptions = ["1000", "2000", "3900", "5200", "6400", "7700", "8000", "12000"]
    
    init(game: GameState, onSettlementComplete: ((Bool) -> Void)? = nil) {
        self.game = game
        self.onSettlementComplete = onSettlementComplete
        _winType = State(initialValue: game.lastWinType)
        _pointInput = State(initialValue: game.lastPointInput)
    }
    
    var body: some View {
        Form {
            Section("快捷结算") {
                Picker("和牌方式", selection: $winType) {
                    ForEach(WinType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                
                if winType == .ron {
                    multiWinnerSelectionRow
                    
                    playerSelectionRow(
                        title: "放铳玩家",
                        selectedIndex: loserIndexBinding.wrappedValue,
                        selectableIndices: availableLoserIndices
                    ) { index in
                        loserIndex = index
                    }
                    
                    ronPointInputs
                } else {
                    playerSelectionRow(
                        title: "胡牌玩家",
                        selectedIndex: winnerIndex,
                        selectableIndices: Array(game.players.indices)
                    ) { index in
                        winnerIndex = index
                    }
                    
                    Text("自摸时不需要选择放铳玩家")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("本次得点")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("例如 3900、8000、12000", text: $pointInput)
                            .keyboardType(.numberPad)
                        
                        Text("当前将按 \(pointInput.isEmpty ? "未输入" : pointInput) 点结算")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    
                    quickPointButtons
                }
            }
            
            Section {
                Button("确认结算") {
                    applySettlement()
                }
                .frame(maxWidth: .infinity)
                .disabled(!canConfirm)
            }
            
            Section {
                DisclosureGroup("快捷结算说明") {
                    Text("这里输入或点击的得点，就是本次直接结算使用的分数。")
                    Text("东家在快捷结算中不会额外乘 1.5 倍。")
                    Text("立直棒会按当前数量一次性加给胡牌者。")
                }
            }
        }
        .navigationTitle("快捷结算")
        .onAppear {
            if !ronWinnerIndices.contains(winnerIndex) {
                ronWinnerIndices = [winnerIndex]
            }
            syncRonPointValues()
        }
        .onChange(of: winnerIndex) {
            fixLoserIfNeeded()
        }
        .onChange(of: winType) {
            fixLoserIfNeeded()
        }
        .onChange(of: ronWinnerIndices) {
            fixLoserIfNeeded()
        }
    }
    
    var availableLoserIndices: [Int] {
        if winType == .ron {
            return game.players.indices.filter { !ronWinnerIndices.contains($0) }
        }
        return game.players.indices.filter { $0 != winnerIndex }
    }
    
    var loserIndexBinding: Binding<Int> {
        Binding(
            get: {
                if availableLoserIndices.contains(loserIndex) {
                    return loserIndex
                }
                return availableLoserIndices.first ?? 0
            },
            set: { newValue in
                loserIndex = newValue
            }
        )
    }
    
    var enteredPoints: Int? {
        Int(pointInput)
    }
    
    func enteredPoints(for winnerIndex: Int) -> Int? {
        Int(ronPointInput(for: winnerIndex))
    }
    
    var quickPointOptions: [String] {
        if game.isEastPlayer(winnerIndex) {
            return eastQuickPointOptions
        }
        return nonEastQuickPointOptions
    }
    
    var canConfirm: Bool {
        if winType == .ron {
            return !ronWinnerIndices.isEmpty
                && loserIndexBinding.wrappedValue != winnerIndex
                && ronWinnerIndices.allSatisfy { (enteredPoints(for: $0) ?? 0) > 0 }
        }
        
        guard let points = enteredPoints, points > 0 else { return false }
        return true
    }
    
    func fixLoserIfNeeded() {
        if winType == .ron, let firstWinner = ronWinnerIndices.first {
            winnerIndex = firstWinner
        }
        
        if let firstAvailableLoser = availableLoserIndices.first,
           loserIndex == winnerIndex || !availableLoserIndices.contains(loserIndex) {
            loserIndex = firstAvailableLoser
        }
    }
    
    func applySettlement() {
        game.lastWinType = winType
        game.lastPointInput = pointInput
        
        let dealerChanged: Bool
        if winType == .ron {
            let settlements: [QuickRonSettlement] = ronWinnerIndices.compactMap { winnerIndex -> QuickRonSettlement? in
                guard let points = enteredPoints(for: winnerIndex), points > 0 else { return nil }
                return QuickRonSettlement(winnerIndex: winnerIndex, points: points)
            }
            dealerChanged = game.settleMultipleRon(
                settlements: settlements,
                loserIndex: loserIndexBinding.wrappedValue
            )
        } else {
            guard let points = enteredPoints, points > 0 else {
                return
            }
            let selectedLoserIndex = winType == .ron ? loserIndex : nil
            dealerChanged = game.settleWin(
                winnerIndex: winnerIndex,
                loserIndex: selectedLoserIndex,
                winType: winType,
                points: points
            )
        }
        
        onSettlementComplete?(dealerChanged)
        dismiss()
    }
    
    @ViewBuilder
    func playerSelectionRow(
        title: String,
        selectedIndex: Int,
        selectableIndices: [Int],
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                ForEach(selectableIndices, id: \.self) { index in
                    Button(game.players[index].name) {
                        onSelect(index)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(index == selectedIndex ? Color.blue.opacity(0.2) : Color.gray.opacity(0.12))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }
            }
        }
    }
    
    var quickPointButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("常用得点")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("点击后会直接替换上面的当前得点")
                .font(.footnote)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(quickPointOptions, id: \.self) { point in
                    Button(point) {
                        pointInput = point
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(pointInput == point ? Color.green.opacity(0.2) : Color.gray.opacity(0.12))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }
            }
        }
    }

    var multiWinnerSelectionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("胡牌玩家")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("荣和时可多选")
                .font(.footnote)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                ForEach(game.players.indices, id: \.self) { index in
                    Button(game.players[index].name) {
                        toggleRonWinner(index)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(ronWinnerIndices.contains(index) ? Color.blue.opacity(0.2) : Color.gray.opacity(0.12))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }
            }
        }
    }

    var ronPointInputs: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("各胡牌者得点")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ForEach(ronWinnerIndices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    Text(game.players[index].name)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    TextField("输入该玩家荣和得点", text: ronPointBinding(for: index))
                        .keyboardType(.numberPad)
                    Text("当前：\(ronPointInput(for: index).isEmpty ? "未输入" : ronPointInput(for: index)) 点")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    func toggleRonWinner(_ index: Int) {
        if ronWinnerIndices.contains(index) {
            if ronWinnerIndices.count > 1 {
                ronWinnerIndices.removeAll { $0 == index }
            }
        } else {
            ronWinnerIndices.append(index)
        }
        syncRonPointValues()
        fixLoserIfNeeded()
    }

    func ronPointInput(for winnerIndex: Int) -> String {
        ronPointValues[winnerIndex] ?? pointInput
    }

    func ronPointBinding(for winnerIndex: Int) -> Binding<String> {
        Binding(
            get: {
                ronPointInput(for: winnerIndex)
            },
            set: { newValue in
                ronPointValues[winnerIndex] = newValue
            }
        )
    }

    func syncRonPointValues() {
        for index in ronWinnerIndices where ronPointValues[index] == nil {
            ronPointValues[index] = pointInput
        }
    }
}

struct FormalScoringView: View {
    @ObservedObject var game: GameState
    var draft: FormalScoringDraft? = nil
    var onSettlementComplete: ((Bool) -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @State private var showingPatternInput = false
    @State private var showingPhotoInput = false
    @State private var winnerIndex = 0
    @State private var ronWinnerEntries: [FormalWinnerEntry] = []
    @State private var winType: WinType = .ron
    @State private var loserIndex = 0
    @State private var hanInput = "1"
    @State private var fuInput = "30"
    @State private var handPatternDraft = HandPatternDraft()
    @State private var ronWinnerDrafts: [Int: HandPatternDraft] = [:]
    @State private var completedPatternWinnerIndices: Set<Int> = []
    @State private var patternInputEntryMode: PatternInputEntryMode = .manual
    @State private var detectedYakuNames: [String] = []
    @State private var detectedNotes: [String] = []
    @State private var detectedYakumanMultiplier = 0
    @State private var didConfigureInitialState = false
    
    private let hanOptions = Array(1...13)
    private let fuOptions = [20, 25, 30, 40, 50, 60, 70, 80, 90, 100, 110]

    var orderedRonWinnerIndices: [Int] {
        ronWinnerEntries.map(\.winnerIndex).sorted()
    }

    var needsSequentialRonPatternInput: Bool {
        winType == .ron && ronWinnerEntries.count > 1
    }

    var allRonPatternsCompleted: Bool {
        let winners = Set(orderedRonWinnerIndices)
        return !winners.isEmpty && winners.isSubset(of: completedPatternWinnerIndices)
    }

    var patternInputApplyButtonTitle: String {
        if patternInputEntryMode == .photoAssisted {
            if needsSequentialRonPatternInput, let nextWinner = nextRonWinnerIndex(after: winnerIndex) {
                return "确认牌面并前往\(game.players[nextWinner].name)"
            }
            return "确认牌面并计算"
        }
        if needsSequentialRonPatternInput, let nextWinner = nextRonWinnerIndex(after: winnerIndex) {
            return "保存并前往\(game.players[nextWinner].name)"
        }
        return "保存"
    }

    var patternInputEntryHint: String? {
        guard patternInputEntryMode == .photoAssisted else { return nil }
        return "拍照识别结果已经自动填入。先确认牌面，必要时手动微调；确认后再进入胡牌逻辑。"
    }

    var patternInputWinnerSummaryText: String? {
        guard winType == .ron, !orderedRonWinnerIndices.isEmpty else { return nil }
        let names = orderedRonWinnerIndices.map { game.players[$0].name }
        return "当前胡牌者：\(game.players[winnerIndex].name) · 本次荣和共 \(names.count) 家：\(names.joined(separator: "、"))"
    }

    var currentPatternDraftBinding: Binding<HandPatternDraft> {
        Binding(
            get: {
                if winType == .ron {
                    return ronWinnerDrafts[winnerIndex] ?? HandPatternDraft()
                }
                return handPatternDraft
            },
            set: { newValue in
                if winType == .ron {
                    ronWinnerDrafts[winnerIndex] = newValue
                } else {
                    handPatternDraft = newValue
                }
            }
        )
    }

    func riichiSnapshot(for index: Int) -> RiichiYakuKind {
        if let entry = ronWinnerEntries.first(where: { $0.winnerIndex == index }) {
            return entry.riichiYaku
        }
        if let draft, draft.winnerIndex == index {
            return draft.riichiYaku
        }
        if game.players.indices.contains(index), game.players[index].isRiichi {
            return .riichi
        }
        return .none
    }

    func ippatsuSnapshot(for index: Int) -> Bool {
        if let entry = ronWinnerEntries.first(where: { $0.winnerIndex == index }) {
            return entry.hasIppatsu
        }
        if let draft, draft.winnerIndex == index {
            return draft.hasIppatsu
        }
        return false
    }

    var ronWinnerInputStatusMap: [Int: String] {
        Dictionary(uniqueKeysWithValues: ronWinnerEntries.map { entry in
            let hanText = entry.hanInput.isEmpty ? "未填" : "\(entry.hanInput)番"
            let fuText = entry.fuInput.isEmpty ? "未填" : "\(entry.fuInput)符"
            return (entry.winnerIndex, "\(hanText) \(fuText)")
        })
    }
    
    var body: some View {
        List {
            Section("和牌信息") {
                Picker("和牌方式", selection: $winType) {
                    ForEach(WinType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                
                if winType == .ron {
                    ronWinnerSelectionRow
                    
                    playerSelectionRow(
                        title: "放铳玩家",
                        selectedIndex: loserIndexBinding.wrappedValue,
                        selectableIndices: availableLoserIndices
                    ) { index in
                        loserIndex = index
                    }
                    
                    ronWinnerInputsSection
                } else {
                    playerSelectionRow(
                        title: "胡牌玩家",
                        selectedIndex: winnerIndex,
                        selectableIndices: Array(game.players.indices)
                    ) { index in
                        winnerIndex = index
                    }
                }
            }
            
            if winType == .tsumo {
                Section("番符输入") {
                    Button("手动输入牌型") {
                        if let firstWinner = orderedRonWinnerIndices.first {
                            winnerIndex = firstWinner
                        }
                        patternInputEntryMode = .manual
                        showingPatternInput = true
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("拍照识别牌型") {
                        showingPhotoInput = true
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Picker("番数", selection: $hanInput) {
                        ForEach(hanOptions, id: \.self) { han in
                            Text("\(han) 番").tag(String(han))
                        }
                    }
                    
                    Picker("符数", selection: $fuInput) {
                        ForEach(fuOptions, id: \.self) { fu in
                            Text("\(fu) 符").tag(String(fu))
                        }
                    }
                }
            } else {
                Section("牌型输入") {
                    Button("手动输入牌型") {
                        if let firstWinner = orderedRonWinnerIndices.first {
                            winnerIndex = firstWinner
                        }
                        patternInputEntryMode = .manual
                        showingPatternInput = true
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("拍照识别牌型") {
                        showingPhotoInput = true
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("当前最小版本按门前手设计：先录入 13 张手牌，再单独录入最后 1 张和牌。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text("拍照识别后会进入同一套牌型编辑页，先确认/微调牌面，再进入正式算分。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("当前牌局状态") {
                if winType == .ron, !multiRonPreviews.isEmpty {
                    ForEach(multiRonPreviews.indices, id: \.self) { index in
                        compactWinnerSummaryCard(
                            winnerIdentity: winnerIdentityText(for: multiRonPreviews[index].winnerIndex),
                            detectedText: compactDetectedText(for: multiRonPreviews[index].winnerIndex),
                            preview: multiRonPreviews[index]
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                } else if let scorePreview = scorePreview {
                    compactWinnerSummaryCard(
                        winnerIdentity: currentWinnerIdentityText,
                        detectedText: compactDetectedText(for: winnerIndex),
                        preview: scorePreview
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                } else {
                    compactWinnerSummaryCard(
                        winnerIdentity: currentWinnerIdentityText,
                        detectedText: compactDetectedText(for: winnerIndex),
                        preview: nil
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
            
            Section {
                Button("确认结算") {
                    applyFormalSettlement()
                }
                .frame(maxWidth: .infinity)
                .disabled(!canConfirmFormalScore)
            }
            
            Section("说明") {
                Text("这是一版最小可用正式算分：手动输入番数和符数，再按庄闲、自摸/荣和、本场和立直棒自动结算。")
            }
        }
        .navigationTitle("正式算分")
        .onAppear {
            guard !didConfigureInitialState else { return }
            DispatchQueue.main.async {
                configureInitialState()
                didConfigureInitialState = true
            }
        }
        .onChange(of: winnerIndex) {
            fixLoserIfNeeded()
            loadCurrentPatternDraftIfNeeded()
        }
        .onChange(of: winType) {
            fixLoserIfNeeded()
        }
        .sheet(isPresented: $showingPatternInput) {
            NavigationStack {
                HandPatternInputView(
                    game: game,
                    winnerIndex: $winnerIndex,
                    winType: winType,
                    draft: currentPatternDraftBinding,
                    entryMode: patternInputEntryMode,
                    entryHint: patternInputEntryHint,
                    applyButtonTitle: patternInputApplyButtonTitle,
                    winnerSummaryText: patternInputWinnerSummaryText,
                    selectableWinnerIndices: winType == .ron ? orderedRonWinnerIndices : [winnerIndex],
                    winnerInputStatusMap: ronWinnerInputStatusMap,
                    allWinnerDrafts: ronWinnerDrafts
                ) { result in
                    applyPatternDetectionResult(result)
                    detectedYakuNames = result.yakuNames
                    detectedNotes = result.notes
                    detectedYakumanMultiplier = result.yakumanMultiplier
                    handlePatternInputCompletion()
                }
                .id("pattern-\(winnerIndex)")
            }
        }
        .sheet(isPresented: $showingPhotoInput) {
            NavigationStack {
                PhotoRecognitionView(
                    context: PhotoRecognitionContext(
                        roundText: game.roundText,
                        honbaCount: game.honbaCount,
                        riichiStickCount: game.riichiStickCount,
                        winnerIdentity: winnerIdentityText(for: winnerIndex)
                    )
                ) { result in
                    var importedDraft = PhotoRecognitionImport.makeHandPatternDraft(from: result) ?? HandPatternDraft()
                    let importedTileCount =
                        importedDraft.handCounts.values.reduce(0, +)
                        + importedDraft.openCounts.values.reduce(0, +)
                        + (importedDraft.winningTile == nil ? 0 : 1)

                    let preservedRiichi = riichiSnapshot(for: winnerIndex)
                    let preservedIppatsu = ippatsuSnapshot(for: winnerIndex)
                    importedDraft.riichiYaku = preservedRiichi
                    if preservedIppatsu {
                        importedDraft.selectedCircumstantialYaku.insert(.ippatsu)
                    } else {
                        importedDraft.selectedCircumstantialYaku.remove(.ippatsu)
                    }

                    patternInputEntryMode = .photoAssisted
                    if winType == .ron {
                        ronWinnerDrafts[winnerIndex] = importedDraft
                        if let entryIndex = ronWinnerEntries.firstIndex(where: { $0.winnerIndex == winnerIndex }) {
                            ronWinnerEntries[entryIndex].detectedText = importedTileCount > 0 ? "已回填拍照识别牌面" : "识别结果为空，已进入手动微调"
                        }
                    } else {
                        handPatternDraft = importedDraft
                    }
                    detectedYakuNames = importedTileCount > 0 ? ["已回填拍照识别牌面"] : []
                    detectedNotes = result.notes + [
                        importedTileCount > 0
                        ? "识别牌面已经回填到牌型输入草稿，可以继续手动微调。"
                        : "这次拍照结果没有稳定回填出牌面，已进入手动微调页。"
                    ]
                    showingPhotoInput = false
                    DispatchQueue.main.async {
                        showingPatternInput = true
                    }
                }
            }
        }
    }
    
    func labelRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    func compactWinnerSummaryCard(
        winnerIdentity: String,
        detectedText: String,
        preview: FormalScoreResult?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                compactTopMetric(title: "当前局", detail: game.roundText)
                compactTopMetric(title: "本场", detail: "\(game.honbaCount)")
                compactTopMetric(title: "立直棒", detail: "\(game.riichiStickCount)")
                compactTopMetric(title: "胡牌者", detail: winnerIdentity)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("役种识别")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(detectedText)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if let preview {
                compactPreviewPanel(preview)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.75))
        .cornerRadius(12)
    }

    func compactPreviewPanel(_ scorePreview: FormalScoreResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("结算预览")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(scorePreview.limitName ?? "\(scorePreview.han) 番 \(scorePreview.fu) 符")")
                .font(.headline)
                .bold()

            if scorePreview.winType == .ron {
                compactPreviewRow(
                    title: "放铳",
                    detail: "\(seatShortText(for: scorePreview.loserIndex)) \(formattedPoints(scorePreview.loserPayment ?? 0)) 点"
                )
            } else if scorePreview.isEastWin {
                compactPreviewRow(
                    title: "三家支付",
                    detail: "各 \(formattedPoints(scorePreview.nonDealerPayment ?? 0)) 点"
                )
            } else {
                compactPreviewRow(
                    title: "庄家支付",
                    detail: "\(formattedPoints(scorePreview.dealerPayment ?? 0)) 点"
                )
                compactPreviewRow(
                    title: "闲家支付",
                    detail: "各 \(formattedPoints(scorePreview.nonDealerPayment ?? 0)) 点"
                )
            }

            compactPreviewRow(
                title: "场供",
                detail: "\(scorePreview.honbaCount) 本场 + \(scorePreview.riichiStickCount) 立直棒"
            )
            Divider()
            Text("总获得 \(formattedPoints(scorePreview.winnerGain)) 点")
                .font(.headline)
                .bold()
        }
    }

    func compactTopMetric(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(detail)
                .font(.subheadline)
                .bold()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func compactPreviewRow(title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(detail)
                .font(.subheadline)
                .bold()
        }
    }

    func formattedPoints(_ value: Int) -> String {
        value.formatted()
    }

    func seatShortText(for index: Int?) -> String {
        guard let index, game.players.indices.contains(index) else { return "-" }
        return String(game.players[index].name.prefix(1))
    }

    func winnerIdentityText(for index: Int) -> String {
        guard game.players.indices.contains(index) else { return "-" }
        let seat = seatShortText(for: index)
        return game.isEastPlayer(index) ? "\(seat)(庄)" : "\(seat)(闲)"
    }

    func compactDetectedText(for winnerIndex: Int) -> String {
        if winType == .ron,
           let entry = ronWinnerEntries.first(where: { $0.winnerIndex == winnerIndex }) {
            if !entry.detectedText.isEmpty {
                return entry.detectedText
            }
            if !entry.hanInput.isEmpty || !entry.fuInput.isEmpty {
                return "手动输入"
            }
            return "等待输入"
        }
        let names = detectedYakuNames
        if !names.isEmpty {
            return names.joined(separator: "、")
        }
        if let firstNote = detectedNotes.first, !firstNote.isEmpty {
            return firstNote
        }
        return game.players.indices.contains(winnerIndex) ? "等待输入" : "-"
    }

    func applyPatternDetectionResult(_ result: PatternDetectionResult) {
        if winType == .ron {
            if let entryIndex = ronWinnerEntries.firstIndex(where: { $0.winnerIndex == winnerIndex }) {
                ronWinnerEntries[entryIndex].hanInput = "\(result.han)"
                ronWinnerEntries[entryIndex].fuInput = "\(result.fu)"
                ronWinnerEntries[entryIndex].yakumanMultiplier = result.yakumanMultiplier
                ronWinnerEntries[entryIndex].detectedText = result.yakuNames.joined(separator: "、")
            } else {
                ronWinnerEntries.append(
                    FormalWinnerEntry(
                        winnerIndex: winnerIndex,
                        hanInput: "\(result.han)",
                        fuInput: "\(result.fu)",
                        yakumanMultiplier: result.yakumanMultiplier,
                        detectedText: result.yakuNames.joined(separator: "、")
                    )
                )
            }
        } else {
            hanInput = "\(result.han)"
            fuInput = "\(result.fu)"
            detectedYakumanMultiplier = result.yakumanMultiplier
        }
    }
    
    var availableLoserIndices: [Int] {
        if winType == .ron {
            let selectedWinnerIndices = ronWinnerEntries.map(\.winnerIndex)
            return game.players.indices.filter { !selectedWinnerIndices.contains($0) }
        }
        return game.players.indices.filter { $0 != winnerIndex }
    }
    
    var loserIndexBinding: Binding<Int> {
        Binding(
            get: {
                if availableLoserIndices.contains(loserIndex) {
                    return loserIndex
                }
                return availableLoserIndices.first ?? 0
            },
            set: { newValue in
                loserIndex = newValue
            }
        )
    }
    
    var enteredHan: Int? {
        Int(hanInput)
    }
    
    var enteredFu: Int? {
        Int(fuInput)
    }
    
    var scorePreview: FormalScoreResult? {
        guard let han = enteredHan, let fu = enteredFu else { return nil }
        return game.calculateFormalScore(
            winnerIndex: winnerIndex,
            loserIndex: winType == .ron ? loserIndexBinding.wrappedValue : nil,
            winType: winType,
            han: han,
            fu: fu,
            yakumanMultiplier: detectedYakumanMultiplier
        )
    }

    var multiRonPreviews: [FormalScoreResult] {
        let winnerInputs = ronWinnerEntries.compactMap { entry -> (winnerIndex: Int, han: Int, fu: Int, yakumanMultiplier: Int)? in
            guard let han = Int(entry.hanInput), let fu = Int(entry.fuInput), han > 0 else {
                return nil
            }
            return (entry.winnerIndex, han, fu, entry.yakumanMultiplier)
        }
        return game.calculateMultipleFormalRon(
            losersIndex: loserIndexBinding.wrappedValue,
            winnerInputs: winnerInputs
        )
    }
    
    var canConfirmFormalScore: Bool {
        if winType == .ron {
            return !ronWinnerEntries.isEmpty
                && loserIndexBinding.wrappedValue != winnerIndex
                && ronWinnerEntries.allSatisfy {
                    let han = Int($0.hanInput) ?? 0
                    let fu = Int($0.fuInput) ?? 0
                    return $0.yakumanMultiplier > 0 ? han > 0 : (han >= 13 ? han > 0 : (han > 0 && fu > 0))
                }
        }
        guard let han = enteredHan, let fu = enteredFu else { return false }
        guard detectedYakumanMultiplier > 0 ? han > 0 : (han >= 13 ? han > 0 : (han > 0 && fu > 0)) else { return false }
        return true
    }
    
    var currentWinnerIdentityText: String {
        if winType == .ron {
            let labels = ronWinnerEntries.map { winnerIdentityText(for: $0.winnerIndex) }
            return labels.joined(separator: "、")
        }
        return winnerIdentityText(for: winnerIndex)
    }
    
    func configureInitialState() {
        if let draft {
            winnerIndex = draft.winnerIndex
            winType = draft.winType
            loserIndex = draft.loserIndex ?? availableLoserIndices.first ?? 0
            ronWinnerEntries = [
                FormalWinnerEntry(
                    winnerIndex: draft.winnerIndex,
                    hanInput: "",
                    fuInput: "",
                    detectedText: "",
                    riichiYaku: draft.riichiYaku,
                    hasIppatsu: draft.hasIppatsu
                )
            ]
            handPatternDraft.riichiYaku = draft.riichiYaku
            if draft.hasIppatsu {
                handPatternDraft.selectedCircumstantialYaku.insert(.ippatsu)
            } else {
                handPatternDraft.selectedCircumstantialYaku.remove(.ippatsu)
            }
        } else {
            winnerIndex = 0
            winType = .ron
            loserIndex = 1
            ronWinnerEntries = [
                FormalWinnerEntry(
                    winnerIndex: 0,
                    hanInput: "",
                    fuInput: "",
                    detectedText: "",
                    riichiYaku: riichiSnapshot(for: 0),
                    hasIppatsu: ippatsuSnapshot(for: 0)
                )
            ]
            handPatternDraft.riichiYaku = riichiSnapshot(for: 0)
            if ippatsuSnapshot(for: 0) {
                handPatternDraft.selectedCircumstantialYaku.insert(.ippatsu)
            } else {
                handPatternDraft.selectedCircumstantialYaku.remove(.ippatsu)
            }
        }
        loadCurrentPatternDraftIfNeeded()
        fixLoserIfNeeded()
    }
    
    func fixLoserIfNeeded() {
        if winType == .ron {
            let winnerIndices = ronWinnerEntries.map(\.winnerIndex)
            if !winnerIndices.contains(winnerIndex), let firstWinner = winnerIndices.first {
                winnerIndex = firstWinner
            }
            completedPatternWinnerIndices = completedPatternWinnerIndices.intersection(Set(winnerIndices))
        }
        
        if let firstAvailable = availableLoserIndices.first,
           loserIndex == winnerIndex || !availableLoserIndices.contains(loserIndex) {
            loserIndex = firstAvailable
        }
    }
    
    func applyFormalSettlement() {
        let dealerChanged: Bool
        if winType == .ron {
            let winnerInputs = ronWinnerEntries.compactMap { entry -> (winnerIndex: Int, han: Int, fu: Int, yakumanMultiplier: Int)? in
                guard let han = Int(entry.hanInput), let fu = Int(entry.fuInput) else { return nil }
                return (entry.winnerIndex, han, fu, entry.yakumanMultiplier)
            }
            dealerChanged = game.settleMultipleFormalRon(
                loserIndex: loserIndexBinding.wrappedValue,
                winnerInputs: winnerInputs
            )
        } else {
            guard let han = enteredHan, let fu = enteredFu else { return }
            dealerChanged = game.settleFormalScore(
                winnerIndex: winnerIndex,
                loserIndex: nil,
                winType: winType,
                han: han,
                fu: fu,
                yakumanMultiplier: detectedYakumanMultiplier
            )
        }
        
        onSettlementComplete?(dealerChanged)
        dismiss()
    }
    
    @ViewBuilder
    func playerSelectionRow(
        title: String,
        selectedIndex: Int,
        selectableIndices: [Int],
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                ForEach(selectableIndices, id: \.self) { index in
                    Button(game.players[index].name) {
                        onSelect(index)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(index == selectedIndex ? Color.green.opacity(0.2) : Color.gray.opacity(0.12))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }
            }
        }
    }

    var ronWinnerSelectionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("胡牌玩家")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("荣和时可多选")
                .font(.footnote)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                ForEach(game.players.indices, id: \.self) { index in
                    Button(game.players[index].name) {
                        toggleFormalRonWinner(index)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(ronWinnerEntries.contains(where: { $0.winnerIndex == index }) ? Color.green.opacity(0.2) : Color.gray.opacity(0.12))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }
            }
        }
    }

    var ronWinnerInputsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("各胡牌者番符")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ForEach($ronWinnerEntries) { $entry in
                VStack(alignment: .leading, spacing: 8) {
                    Text(game.players[entry.winnerIndex].name)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    Picker("番数", selection: $entry.hanInput) {
                        Text("未填写").tag("")
                        ForEach(hanOptions, id: \.self) { han in
                            Text("\(han) 番").tag(String(han))
                        }
                    }
                    
                    Picker("符数", selection: $entry.fuInput) {
                        Text("未填写").tag("")
                        ForEach(fuOptions, id: \.self) { fu in
                            Text("\(fu) 符").tag(String(fu))
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    func toggleFormalRonWinner(_ index: Int) {
        if let existingIndex = ronWinnerEntries.firstIndex(where: { $0.winnerIndex == index }) {
            winnerIndex = index
            if ronWinnerEntries.count > 1 {
                ronWinnerEntries.remove(at: existingIndex)
                ronWinnerDrafts.removeValue(forKey: index)
                completedPatternWinnerIndices.remove(index)
                if winnerIndex == index, let firstWinner = ronWinnerEntries.first?.winnerIndex {
                    winnerIndex = firstWinner
                }
            }
        } else {
            ronWinnerEntries.append(
                FormalWinnerEntry(
                    winnerIndex: index,
                    hanInput: "",
                    fuInput: "",
                    detectedText: "",
                    riichiYaku: riichiSnapshot(for: index),
                    hasIppatsu: ippatsuSnapshot(for: index)
                )
            )
            winnerIndex = index
        }
        fixLoserIfNeeded()
    }

    func loadCurrentPatternDraftIfNeeded() {
        if winType == .ron, ronWinnerDrafts[winnerIndex] == nil {
            var newDraft = HandPatternDraft()
            if let entry = ronWinnerEntries.first(where: { $0.winnerIndex == winnerIndex }) {
                newDraft.riichiYaku = entry.riichiYaku
                if entry.hasIppatsu {
                    newDraft.selectedCircumstantialYaku.insert(.ippatsu)
                }
            }
            ronWinnerDrafts[winnerIndex] = newDraft
        } else if winType == .ron,
                  var existingDraft = ronWinnerDrafts[winnerIndex],
                  let entry = ronWinnerEntries.first(where: { $0.winnerIndex == winnerIndex }) {
            existingDraft.riichiYaku = entry.riichiYaku
            if entry.hasIppatsu {
                existingDraft.selectedCircumstantialYaku.insert(.ippatsu)
            } else {
                existingDraft.selectedCircumstantialYaku.remove(.ippatsu)
            }
            ronWinnerDrafts[winnerIndex] = existingDraft
        } else if winType == .tsumo {
            if let draft {
                handPatternDraft.riichiYaku = draft.riichiYaku
                if draft.hasIppatsu {
                    handPatternDraft.selectedCircumstantialYaku.insert(.ippatsu)
                } else {
                    handPatternDraft.selectedCircumstantialYaku.remove(.ippatsu)
                }
            } else {
                handPatternDraft.riichiYaku = riichiSnapshot(for: winnerIndex)
                if ippatsuSnapshot(for: winnerIndex) {
                    handPatternDraft.selectedCircumstantialYaku.insert(.ippatsu)
                } else {
                    handPatternDraft.selectedCircumstantialYaku.remove(.ippatsu)
                }
            }
        }
    }

    func nextRonWinnerIndex(after currentWinnerIndex: Int) -> Int? {
        guard let currentPosition = orderedRonWinnerIndices.firstIndex(of: currentWinnerIndex) else {
            return orderedRonWinnerIndices.first
        }
        let nextPosition = orderedRonWinnerIndices.index(after: currentPosition)
        guard nextPosition < orderedRonWinnerIndices.endIndex else { return nil }
        return orderedRonWinnerIndices[nextPosition]
    }

    func handlePatternInputCompletion() {
        if winType == .ron {
            completedPatternWinnerIndices.insert(winnerIndex)
            if let nextWinner = nextRonWinnerIndex(after: winnerIndex) {
                winnerIndex = nextWinner
                patternInputEntryMode = .manual
                loadCurrentPatternDraftIfNeeded()
                return
            }
        }
        patternInputEntryMode = .manual
        showingPatternInput = false
    }
}

struct HandPatternInputView: View {
    @ObservedObject var game: GameState
    @Binding var winnerIndex: Int
    var winType: WinType
    @Binding var draft: HandPatternDraft
    var entryMode: PatternInputEntryMode = .manual
    var entryHint: String? = nil
    var applyButtonTitle = "应用到正式算分"
    var winnerSummaryText: String? = nil
    var selectableWinnerIndices: [Int] = []
    var winnerInputStatusMap: [Int: String] = [:]
    var allWinnerDrafts: [Int: HandPatternDraft] = [:]
    var onApply: (PatternDetectionResult) -> Void
    
    @Environment(\.dismiss) private var dismiss
    var winnerHasRiichi: Bool {
        draft.riichiYaku != .none
    }

    var otherWinnerDrafts: [HandPatternDraft] {
        selectableWinnerIndices
            .filter { $0 != winnerIndex }
            .compactMap { allWinnerDrafts[$0] }
    }

    var sharedRonWinningTile: MahjongTile? {
        guard winType == .ron else { return nil }
        let tiles = otherWinnerDrafts.compactMap(\.winningTile)
        guard let first = tiles.first else { return nil }
        return tiles.allSatisfy { $0 == first } ? first : first
    }

    var availableTileSections: [TileInputSection] {
        winnerHasRiichi ? [.concealed, .openMeld, .winning] : TileInputSection.allCases
    }

    func sectionTitle(_ section: TileInputSection) -> String {
        switch section {
        case .concealed:
            return "手牌"
        case .openMeld:
            return winnerHasRiichi ? "暗杠" : "副露"
        case .winning:
            return "胡牌"
        }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    entryHeaderSection
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            Color.clear
                                .frame(height: 1)
                                .id("pattern-picker-top")

                            ForEach(Array(MahjongTile.groupedTiles.enumerated()), id: \.offset) { _, tiles in
                                VStack(alignment: .leading, spacing: 8) {
                                    let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

                                    LazyVGrid(columns: columns, spacing: 8) {
                                        if tiles.first?.isHonor == true {
                                            ForEach(tiles) { tile in
                                                tilePickerCard(tile)
                                            }
                                            bonusCounterCard(
                                                title: "宝牌数",
                                                count: draft.doraCount,
                                                onDecrease: { draft.doraCount = max(0, draft.doraCount - 1) },
                                                onIncrease: { draft.doraCount += 1 }
                                            )
                                            bonusCounterCard(
                                                title: "红宝牌数",
                                                count: draft.redDoraCount,
                                                onDecrease: { draft.redDoraCount = max(0, draft.redDoraCount - 1) },
                                                onIncrease: { draft.redDoraCount += 1 }
                                            )
                                        } else {
                                            ForEach(tiles) { tile in
                                                tilePickerCard(tile)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    } header: {
                        stickySelectionSection
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .background(Color(red: 0.96, green: 0.93, blue: 0.83))
                    }
                }
            }
            .onChange(of: draft.activeSection) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo("pattern-picker-top", anchor: .top)
                }
            }
        }
        .background(Color(red: 0.96, green: 0.93, blue: 0.83).ignoresSafeArea())
        .navigationTitle(entryMode == .photoAssisted ? "确认/微调牌面" : "牌型输入")
        .onAppear {
            sanitizeDraft()
            refreshAnalysisAfterMetadataChange()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭") {
                    dismiss()
                }
            }
        }
        .onChange(of: winnerIndex) {
            DispatchQueue.main.async {
                sanitizeDraft()
                refreshAnalysisAfterMetadataChange()
            }
        }
    }
    
    var entryHeaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entryMode == .photoAssisted ? "拍照结果已自动填入" : (winnerHasRiichi ? "当前最小版本支持：手牌 / 暗杠 / 胡牌 三块输入" : "当前最小版本支持：手牌 / 副露 / 胡牌 三块输入"))
                .font(.headline)
            if let entryHint {
                Text(entryHint)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            if let winnerSummaryText {
                Text(winnerSummaryText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Text(winnerHasRiichi ? "立直后胡牌不再录入吃/碰/明杠，只保留暗杠入口。暗杠仍按门前清处理，也可以继续立直。最后再选 1 张胡牌。" : "建议先录入手牌和副露。若有杠子，目标张数会自动变成 13 + 杠子数；最后再选 1 张胡牌。")
                .font(.footnote)
                .foregroundColor(.secondary)
            Picker("输入区域", selection: $draft.activeSection) {
                ForEach(availableTileSections) { section in
                    Text(sectionTitle(section)).tag(section)
                }
            }
            .pickerStyle(.segmented)
            
            if draft.activeSection == .openMeld {
                Text(winnerHasRiichi ? "这里仅录入暗杠。手牌里凑到 4 张相同牌后，可单独设为暗杠。" : "副露区域直接点牌录入。4 张相同牌默认按明杠处理，其余会自动整理成碰或顺子。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 10) {
                sectionSummaryCard(
                    title: "手牌",
                    countText: "\(totalHandCount) 张",
                    detailText: concealedKongCount > 0 ? "杠子 \(concealedKongCount) 组" : "未成杠",
                    isActive: draft.activeSection == .concealed,
                    action: { draft.activeSection = .concealed }
                )
                sectionSummaryCard(
                    title: winnerHasRiichi ? "暗杠" : "副露",
                    countText: "\(totalOpenCount) 张",
                    detailText: openKongCount > 0 ? "杠子 \(openKongCount) 组" : "未成杠",
                    isActive: draft.activeSection == .openMeld,
                    action: { draft.activeSection = .openMeld }
                )
                sectionSummaryCard(
                    title: "胡牌",
                    countText: draft.winningTile?.label ?? "未选",
                    detailText: "最后选择",
                    isActive: draft.activeSection == .winning,
                    action: { draft.activeSection = .winning }
                )
            }
            
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("总牌数：\(totalTileCount) / \(requiredTileCountBeforeWin)")
                    Text("杠子数：\(totalKongCount) 组")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    HStack(spacing: 16) {
                        labelValueBlock(title: "宝牌", value: "宝：\(draft.doraCount)")
                        labelValueBlock(title: "红宝牌", value: "红宝：\(draft.redDoraCount)")
                    }
                    HStack(spacing: 16) {
                        labelValueBlock(title: "胡牌者", value: game.players[winnerIndex].name)
                        labelValueBlock(title: "和牌方式", value: winType.rawValue)
                    }
                    if selectableWinnerIndices.count > 1 {
                        winnerSelectionButtons
                    }
                }
                
                if let analysisResult = draft.analysisResult {
                    compactAnalysisBlock(analysisResult)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.7))
        .cornerRadius(14)
    }

    var stickySelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            selectedTilesStrip
            
            HStack(spacing: 12) {
                Button(applyButtonTitle) {
                    onApply(analysisResultForApply())
                }
                .font(.footnote)
                .buttonStyle(.borderedProminent)
                .disabled(!hasAnyTileInput)

                Spacer()

                Button("清空输入") {
                    draft = HandPatternDraft()
                }
                .font(.footnote)
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.white.opacity(0.7))
        .cornerRadius(14)
    }

    var winnerSelectionButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("切换胡牌者")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                ForEach(selectableWinnerIndices, id: \.self) { index in
                    Button {
                        winnerIndex = index
                    } label: {
                        VStack(spacing: 2) {
                            Text(game.players[index].name)
                                .font(.subheadline)
                                .bold()
                            if let status = winnerInputStatusMap[index] {
                                Text(status)
                                    .font(.caption2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(index == winnerIndex ? Color.orange.opacity(0.18) : Color.gray.opacity(0.12))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
            }
        }
    }

    func labelValueBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if title == "胡牌者" || title == "和牌方式" {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(title == "胡牌者" || title == "和牌方式" ? .title3 : .headline)
                .bold()
        }
    }

    func compactAnalysisBlock(_ analysisResult: PatternDetectionResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(analysisSummaryText(for: analysisResult))
                .font(.headline)
                .bold()
            if analysisResult.yakuNames != ["无役"] {
                Text(analysisResult.yakuNames.joined(separator: "、"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            } else {
                Text("条件役")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                inlineCircumstantialYakuButtons
            }
            if analysisResult.yakuNames != ["无役"], let firstNote = analysisResult.notes.first {
                Text(firstNote)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.82))
        .cornerRadius(12)
    }

    func analysisSummaryText(for result: PatternDetectionResult) -> String {
        if result.yakuNames == ["无役"] {
            return "无役"
        }
        return "\(result.han)番 \(result.fu)符"
    }

    var inlineCircumstantialYakuButtons: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(CircumstantialYaku.allCases) { yaku in
                Button {
                    toggleCircumstantialYaku(yaku)
                } label: {
                    Text(yaku.rawValue)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            draft.selectedCircumstantialYaku.contains(yaku)
                            ? Color.orange.opacity(0.18)
                            : Color.white.opacity(0.82)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    draft.selectedCircumstantialYaku.contains(yaku)
                                    ? Color.orange.opacity(0.7)
                                    : Color.gray.opacity(0.15),
                                    lineWidth: 1
                                )
                        )
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    var selectedTilesStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            smallTileRow(title: "手牌", tiles: selectedConcealedTiles, section: .concealed)
            smallTileRow(title: winnerHasRiichi ? "暗杠" : "副露", tiles: selectedOpenTiles, section: .openMeld)
            smallTileRow(title: "胡牌", tiles: draft.winningTile.map { [$0] } ?? [], section: .winning)
        }
    }

    func smallTileRow(title: String, tiles: [MahjongTile], section: TileInputSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    if tiles.isEmpty {
                        Color.clear
                            .frame(height: 30)
                    } else {
                        ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                            remoteTileFace(tile, height: 30)
                                .frame(width: 20)
                        }
                    }
                }
            }
            .frame(minHeight: 30)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(draft.activeSection == section ? 0.98 : 0.8))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(draft.activeSection == section ? Color.orange.opacity(0.6) : Color.clear, lineWidth: 1.5)
        }
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            draft.activeSection = section
        }
    }

    var selectedConcealedTiles: [MahjongTile] {
        sortedTilesForDisplay.flatMap { tile in
            Array(repeating: tile, count: draft.handCounts[tile, default: 0])
        }
    }

    var hasAnyTileInput: Bool {
        totalTileCount > 0 || draft.winningTile != nil
    }

    var selectedOpenTiles: [MahjongTile] {
        sortedTilesForDisplay.flatMap { tile in
            Array(repeating: tile, count: draft.openCounts[tile, default: 0])
        }
    }

    var sortedTilesForDisplay: [MahjongTile] {
        MahjongTile.allCases.sorted(by: tileDisplayOrder(_:_:))
    }

    func tileDisplayOrder(_ lhs: MahjongTile, _ rhs: MahjongTile) -> Bool {
        tileSortKey(lhs) < tileSortKey(rhs)
    }

    func tileSortKey(_ tile: MahjongTile) -> (Int, Int) {
        switch tile {
        case .man1: return (0, 1)
        case .man2: return (0, 2)
        case .man3: return (0, 3)
        case .man4: return (0, 4)
        case .man5: return (0, 5)
        case .man6: return (0, 6)
        case .man7: return (0, 7)
        case .man8: return (0, 8)
        case .man9: return (0, 9)
        case .pin1: return (1, 1)
        case .pin2: return (1, 2)
        case .pin3: return (1, 3)
        case .pin4: return (1, 4)
        case .pin5: return (1, 5)
        case .pin6: return (1, 6)
        case .pin7: return (1, 7)
        case .pin8: return (1, 8)
        case .pin9: return (1, 9)
        case .sou1: return (2, 1)
        case .sou2: return (2, 2)
        case .sou3: return (2, 3)
        case .sou4: return (2, 4)
        case .sou5: return (2, 5)
        case .sou6: return (2, 6)
        case .sou7: return (2, 7)
        case .sou8: return (2, 8)
        case .sou9: return (2, 9)
        case .east: return (3, 1)
        case .south: return (3, 2)
        case .west: return (3, 3)
        case .north: return (3, 4)
        case .white: return (3, 5)
        case .green: return (3, 6)
        case .red: return (3, 7)
        }
    }
    
    func sectionSummaryCard(title: String, countText: String, detailText: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.headline)
            Text(countText)
                .font(.subheadline)
                .bold()
            Text(detailText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(isActive ? 0.98 : 0.8))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.orange.opacity(0.6) : Color.clear, lineWidth: 1.5)
        }
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
    
    func tilePickerCard(_ tile: MahjongTile) -> some View {
        let remainingCount = remainingCopiesForCurrentWinner(of: tile)
        
        return VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .frame(height: 74)
                .overlay {
                    VStack(spacing: 2) {
                        remoteTileFace(tile, height: 48)
                        Text("x\(remainingCount)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .shadow(radius: 1)
            
            HStack(spacing: 6) {
                Button("-") {
                    removeTile(tile)
                }
                .buttonStyle(.bordered)
                
                Button("+") {
                    addTile(tile)
                }
                .buttonStyle(.borderedProminent)
            }

            if shouldShowConcealedKanButton(for: tile) {
                Button(draft.concealedKanTiles.contains(tile) ? "已设暗杠" : "设为暗杠") {
                    toggleConcealedKan(tile)
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }

            if let kongAdjustmentTitle = kongAdjustmentButtonTitle(for: tile) {
                Button(kongAdjustmentTitle) {
                    toggleKongExposure(for: tile)
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            
            if shouldShowWinningButton(for: tile) {
                Button(draft.winningTile == tile ? "已选和牌" : "设为和牌") {
                    setWinningTile(tile)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .disabled(draft.activeSection != .winning)
            } else {
                Color.clear
                    .frame(height: 28)
            }
        }
    }

    func remoteTileFace(_ tile: MahjongTile, height: CGFloat) -> some View {
        Group {
            if let assetName = tileAssetName(for: tile), UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            } else {
                fallbackTileFace(tile)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    func fallbackTileFace(_ tile: MahjongTile) -> some View {
        Text(tile.label)
            .font(.headline)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func tileAssetName(for tile: MahjongTile) -> String? {
        switch tile {
        case .man1: return "mahjong_man1"
        case .man2: return "mahjong_man2"
        case .man3: return "mahjong_man3"
        case .man4: return "mahjong_man4"
        case .man5: return "mahjong_man5"
        case .man6: return "mahjong_man6"
        case .man7: return "mahjong_man7"
        case .man8: return "mahjong_man8"
        case .man9: return "mahjong_man9"
        case .pin1: return "mahjong_pin1"
        case .pin2: return "mahjong_pin2"
        case .pin3: return "mahjong_pin3"
        case .pin4: return "mahjong_pin4"
        case .pin5: return "mahjong_pin5"
        case .pin6: return "mahjong_pin6"
        case .pin7: return "mahjong_pin7"
        case .pin8: return "mahjong_pin8"
        case .pin9: return "mahjong_pin9"
        case .sou1: return "mahjong_sou1"
        case .sou2: return "mahjong_sou2"
        case .sou3: return "mahjong_sou3"
        case .sou4: return "mahjong_sou4"
        case .sou5: return "mahjong_sou5"
        case .sou6: return "mahjong_sou6"
        case .sou7: return "mahjong_sou7"
        case .sou8: return "mahjong_sou8"
        case .sou9: return "mahjong_sou9"
        case .east: return "mahjong_east"
        case .south: return "mahjong_south"
        case .west: return "mahjong_west"
        case .north: return "mahjong_north"
        case .white: return "mahjong_white"
        case .green: return "mahjong_green"
        case .red: return "mahjong_red"
        }
    }

    func bonusCounterCard(
        title: String,
        count: Int,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .frame(height: 58)
                .overlay {
                    VStack(spacing: 2) {
                        Text(title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(count)")
                            .font(.headline)
                    }
                }
                .shadow(radius: 1)
            
            HStack(spacing: 6) {
                Button("-") {
                    onDecrease()
                    refreshAnalysisAfterMetadataChange()
                }
                .buttonStyle(.bordered)
                
                Button("+") {
                    onIncrease()
                    refreshAnalysisAfterMetadataChange()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Color.clear
                .frame(height: 28)
        }
    }
    
    var totalHandCount: Int {
        draft.handCounts.values.reduce(0, +)
    }
    
    var totalOpenCount: Int {
        draft.openCounts.values.reduce(0, +)
    }
    
    var totalTileCount: Int {
        totalHandCount + totalOpenCount
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
    
    var canAnalyze: Bool {
        totalTileCount == requiredTileCountBeforeWin && draft.winningTile != nil
    }

    var winningTileCandidates: [(tile: MahjongTile, result: PatternDetectionResult)] {
        guard totalTileCount == requiredTileCountBeforeWin else { return [] }
        var candidates: [(tile: MahjongTile, result: PatternDetectionResult)] = []
        for tile in sortedTilesForDisplay {
            guard handCount(for: tile) + openCount(for: tile) < 4,
                  let result = analyzeHand(forWinningTile: tile) else {
                continue
            }
            candidates.append((tile: tile, result: result))
        }
        if let sharedRonWinningTile {
            return candidates.filter { $0.tile == sharedRonWinningTile }
        }
        return candidates
    }

    var selectableWinningTileSet: Set<MahjongTile> {
        Set(winningTileCandidates.map(\.tile))
    }

    func analysisResultForApply() -> PatternDetectionResult {
        if let result = draft.analysisResult {
            return result
        }

        let note: String
        if totalTileCount == 0 && draft.winningTile == nil {
            note = "当前还没有录入任何牌面。"
        } else if totalTileCount != requiredTileCountBeforeWin {
            note = "当前牌面结构不完整或张数不合法，未识别出可和牌型。"
        } else if draft.winningTile == nil {
            note = "当前牌面尚未选择胡牌，未识别出可和牌型。"
        } else {
            note = "当前牌面未识别出可和牌型。"
        }

        return PatternDetectionResult(
            han: 0,
            fu: 0,
            yakuNames: ["无役"],
            notes: [note]
        )
    }
    
    func handCount(for tile: MahjongTile) -> Int {
        draft.handCounts[tile, default: 0]
    }
    
    func openCount(for tile: MahjongTile) -> Int {
        draft.openCounts[tile, default: 0]
    }
    
    func totalCount(for tile: MahjongTile) -> Int {
        handCount(for: tile) + openCount(for: tile) + (draft.winningTile == tile ? 1 : 0)
    }

    func otherWinnerOccupiedCount(for tile: MahjongTile) -> Int {
        otherWinnerDrafts.reduce(0) { partial, otherDraft in
            partial
            + otherDraft.handCounts[tile, default: 0]
            + otherDraft.openCounts[tile, default: 0]
        }
    }

    func remainingCopiesForCurrentWinner(of tile: MahjongTile) -> Int {
        max(0, 4 - otherWinnerOccupiedCount(for: tile) - totalCount(for: tile))
    }
    
    func addTile(_ tile: MahjongTile) {
        switch draft.activeSection {
        case .concealed:
            addHandTile(tile)
        case .openMeld:
            addOpenTile(tile)
        case .winning:
            if shouldShowWinningButton(for: tile) {
                setWinningTile(tile)
            } else {
                draft.activeSection = .concealed
                addHandTile(tile)
            }
        }
    }
    
    func removeTile(_ tile: MahjongTile) {
        switch draft.activeSection {
        case .winning:
            if draft.winningTile == tile {
                draft.activeSection = .winning
                draft.winningTile = nil
                draft.analysisResult = nil
                return
            }
            if handCount(for: tile) > 0 {
                draft.activeSection = .concealed
                removeHandTile(tile)
                return
            }
            if openCount(for: tile) > 0 {
                draft.activeSection = .openMeld
                removeOpenTile(tile)
                return
            }
        case .concealed:
            if handCount(for: tile) > 0 {
                draft.activeSection = .concealed
                removeHandTile(tile)
                return
            }
            if openCount(for: tile) > 0 {
                draft.activeSection = .openMeld
                removeOpenTile(tile)
                return
            }
            if draft.winningTile == tile {
                draft.activeSection = .winning
                draft.winningTile = nil
                draft.analysisResult = nil
                return
            }
        case .openMeld:
            if openCount(for: tile) > 0 {
                draft.activeSection = .openMeld
                removeOpenTile(tile)
                return
            }
            if handCount(for: tile) > 0 {
                draft.activeSection = .concealed
                removeHandTile(tile)
                return
            }
            if draft.winningTile == tile {
                draft.activeSection = .winning
                draft.winningTile = nil
                draft.analysisResult = nil
                return
            }
        }
    }
    
    func addHandTile(_ tile: MahjongTile) {
        guard canAddTile(toConcealed: true, tile: tile) else { return }
        guard remainingCopiesForCurrentWinner(of: tile) > 0 else { return }
        draft.handCounts[tile, default: 0] += 1
        draft.analysisResult = nil
        updateActiveSectionForCurrentTileCount()
    }
    
    func removeHandTile(_ tile: MahjongTile) {
        guard handCount(for: tile) > 0 else { return }
        draft.handCounts[tile, default: 0] -= 1
        if draft.handCounts[tile] == 0 {
            draft.handCounts.removeValue(forKey: tile)
        }
        draft.analysisResult = nil
        updateActiveSectionForCurrentTileCount()
    }
    
    func addOpenTile(_ tile: MahjongTile) {
        guard canAddTile(toConcealed: false, tile: tile) else { return }
        guard remainingCopiesForCurrentWinner(of: tile) > 0 else { return }
        draft.openCounts[tile, default: 0] += 1
        rebuildOpenMeldGroups()
        draft.analysisResult = nil
        updateActiveSectionForCurrentTileCount()
    }
    
    func removeOpenTile(_ tile: MahjongTile) {
        guard openCount(for: tile) > 0 else { return }
        draft.openCounts[tile, default: 0] -= 1
        if draft.openCounts[tile] == 0 {
            draft.openCounts.removeValue(forKey: tile)
        }
        rebuildOpenMeldGroups()
        draft.analysisResult = nil
        updateActiveSectionForCurrentTileCount()
    }
    
    func setWinningTile(_ tile: MahjongTile) {
        guard totalTileCount == requiredTileCountBeforeWin else { return }
        if let sharedRonWinningTile, tile != sharedRonWinningTile { return }
        guard selectableWinningTileSet.contains(tile) || draft.winningTile == tile else { return }
        guard handCount(for: tile) + openCount(for: tile) + (draft.winningTile == tile ? 0 : 1) <= 4 else {
            return
        }
        draft.winningTile = tile
        draft.analysisResult = analyzeHand(forWinningTile: tile)
    }

    func updateActiveSectionForCurrentTileCount() {
        if totalTileCount == requiredTileCountBeforeWin {
            draft.activeSection = .winning
            refreshWinningGuidance()
        } else if draft.activeSection == .winning {
            draft.activeSection = .concealed
            draft.winningTile = nil
            draft.analysisResult = nil
        }
    }

    func refreshWinningGuidance() {
        guard totalTileCount == requiredTileCountBeforeWin else {
            draft.analysisResult = nil
            return
        }

        if let winningTile = draft.winningTile {
            draft.analysisResult = analyzeHand(forWinningTile: winningTile)
            return
        }

        if !winningTileCandidates.isEmpty {
            draft.analysisResult = nil
            return
        }

        var firstExplainableResult: PatternDetectionResult? = nil
        for tile in sortedTilesForDisplay {
            guard handCount(for: tile) + openCount(for: tile) < 4 else { continue }
            guard let result = analyzeHand(forWinningTile: tile), result.yakuNames == ["无役"] else { continue }
            firstExplainableResult = result
            break
        }

        if let firstExplainableResult {
            draft.analysisResult = firstExplainableResult
        } else {
            draft.analysisResult = PatternDetectionResult(
                han: 0,
                fu: 0,
                yakuNames: ["无役"],
                notes: ["当前手牌未识别到可和的牌型，请检查手牌结构或副露录入。"]
            )
        }
    }

    func refreshAnalysisAfterMetadataChange() {
        if let winningTile = draft.winningTile {
            draft.analysisResult = analyzeHand(forWinningTile: winningTile)
        } else if totalTileCount == requiredTileCountBeforeWin {
            refreshWinningGuidance()
        } else {
            draft.analysisResult = nil
        }
    }

    func toggleCircumstantialYaku(_ yaku: CircumstantialYaku) {
        if draft.selectedCircumstantialYaku.contains(yaku) {
            draft.selectedCircumstantialYaku.remove(yaku)
        } else {
            draft.selectedCircumstantialYaku.insert(yaku)
        }
        refreshAnalysisAfterMetadataChange()
    }

    func shouldShowWinningButton(for tile: MahjongTile) -> Bool {
        guard draft.activeSection == .winning,
              totalTileCount == requiredTileCountBeforeWin else {
            return false
        }
        if draft.winningTile == tile {
            return selectableWinningTileSet.contains(tile)
        }
        return selectableWinningTileSet.contains(tile)
    }

    func shouldShowConcealedKanButton(for tile: MahjongTile) -> Bool {
        draft.activeSection == .concealed && handCount(for: tile) == 4
    }

    func kongAdjustmentButtonTitle(for tile: MahjongTile) -> String? {
        if openCount(for: tile) == 4 {
            return "改为暗杠"
        }
        if handCount(for: tile) == 4, draft.concealedKanTiles.contains(tile) {
            return "改为明杠"
        }
        return nil
    }

    func toggleConcealedKan(_ tile: MahjongTile) {
        if draft.concealedKanTiles.contains(tile) {
            draft.concealedKanTiles.remove(tile)
        } else {
            draft.concealedKanTiles.insert(tile)
        }
        draft.analysisResult = nil
        updateActiveSectionForCurrentTileCount()
    }

    func toggleKongExposure(for tile: MahjongTile) {
        if openCount(for: tile) == 4 {
            draft.openCounts.removeValue(forKey: tile)
            draft.handCounts[tile] = 4
            draft.concealedKanTiles.insert(tile)
        } else if handCount(for: tile) == 4, draft.concealedKanTiles.contains(tile) {
            draft.concealedKanTiles.remove(tile)
            draft.handCounts.removeValue(forKey: tile)
            draft.openCounts[tile] = 4
        } else {
            return
        }

        rebuildOpenMeldGroups()
        draft.analysisResult = nil
        updateActiveSectionForCurrentTileCount()
    }
    
    func canAddTile(toConcealed: Bool, tile: MahjongTile) -> Bool {
        if totalCount(for: tile) >= 4 || remainingCopiesForCurrentWinner(of: tile) <= 0 {
            return false
        }
        
        var projectedHandCounts = draft.handCounts
        var projectedOpenCounts = draft.openCounts
        
        if toConcealed {
            projectedHandCounts[tile, default: 0] += 1
        } else {
            projectedOpenCounts[tile, default: 0] += 1
        }
        
        let projectedKongCount =
            draft.concealedKanTiles.count +
            projectedOpenCounts.values.filter { $0 == 4 }.count
        let projectedTileCount =
            projectedHandCounts.values.reduce(0, +) +
            projectedOpenCounts.values.reduce(0, +)
        
        return projectedTileCount <= 13 + projectedKongCount
    }
    
    func sanitizeDraft() {
        var sanitizedHandCounts: [MahjongTile: Int] = [:]
        var sanitizedOpenCounts: [MahjongTile: Int] = [:]
        
        for tile in MahjongTile.allCases {
            let handCount = max(0, draft.handCounts[tile, default: 0])
            let openCount = max(0, draft.openCounts[tile, default: 0])
            let limitedHand = min(handCount, 4)
            let limitedOpen = min(openCount, max(0, 4 - limitedHand))
            
            if limitedHand > 0 {
                sanitizedHandCounts[tile] = limitedHand
            }
            if limitedOpen > 0 {
                sanitizedOpenCounts[tile] = limitedOpen
            }
        }
        
        draft.handCounts = sanitizedHandCounts
        draft.openCounts = sanitizedOpenCounts
        draft.concealedKanTiles = Set(draft.concealedKanTiles.filter { sanitizedHandCounts[$0, default: 0] == 4 })
        rebuildOpenMeldGroups()
        
        if let winningTile = draft.winningTile,
           handCount(for: winningTile) + openCount(for: winningTile) >= 4 {
            draft.winningTile = nil
        }
        if let sharedRonWinningTile,
           let winningTile = draft.winningTile,
           winningTile != sharedRonWinningTile {
            draft.winningTile = nil
        }
        
        draft.analysisResult = nil
    }
    
    func rebuildOpenMeldGroups() {
        var counts = Array(repeating: 0, count: MahjongTile.allCases.count)
        for (tile, count) in draft.openCounts {
            counts[tile.rawValue] = count
        }
        draft.openMeldGroups = deriveOpenMeldGroups(from: counts)
    }

    func deriveOpenMeldGroups(from counts: [Int]) -> [OpenMeldGroup] {
        allOpenMeldGroupOptions(from: counts).first ?? []
    }

    func allOpenMeldGroupOptions(from counts: [Int]) -> [[OpenMeldGroup]] {
        var working = counts
        var fixedGroups: [OpenMeldGroup] = []

        for index in working.indices where working[index] == 4 {
            if let tile = MahjongTile(rawValue: index) {
                fixedGroups.append(OpenMeldGroup(type: .openKan, tiles: [tile, tile, tile, tile]))
                working[index] = 0
            }
        }

        let remainderOptions = decomposeOpenRemainders(working)
        if remainderOptions.isEmpty {
            if working.contains(where: { $0 > 0 }) {
                return []
            }
            return [fixedGroups]
        }
        return remainderOptions.map { fixedGroups + $0 }
    }

    func decomposeOpenRemainders(_ counts: [Int]) -> [[OpenMeldGroup]] {
        var mutableCounts = counts
        return decomposeOpenRemainders(&mutableCounts)
    }

    func decomposeOpenRemainders(_ counts: inout [Int]) -> [[OpenMeldGroup]] {
        guard let firstIndex = counts.firstIndex(where: { $0 > 0 }) else {
            return [[]]
        }

        var results: [[OpenMeldGroup]] = []

        if counts[firstIndex] >= 3, let tile = MahjongTile(rawValue: firstIndex) {
            counts[firstIndex] -= 3
            for rest in decomposeOpenRemainders(&counts) {
                results.append([OpenMeldGroup(type: .pon, tiles: [tile, tile, tile])] + rest)
            }
            counts[firstIndex] += 3
        }

        if firstIndex < 27 {
            let rank = firstIndex % 9
            if rank <= 6,
               counts[firstIndex + 1] > 0,
               counts[firstIndex + 2] > 0,
               let first = MahjongTile(rawValue: firstIndex),
               let second = MahjongTile(rawValue: firstIndex + 1),
               let third = MahjongTile(rawValue: firstIndex + 2) {
                counts[firstIndex] -= 1
                counts[firstIndex + 1] -= 1
                counts[firstIndex + 2] -= 1
                for rest in decomposeOpenRemainders(&counts) {
                    results.append([OpenMeldGroup(type: .chi, tiles: [first, second, third])] + rest)
                }
                counts[firstIndex] += 1
                counts[firstIndex + 1] += 1
                counts[firstIndex + 2] += 1
            }
        }

        return results
    }
    
    func analyzeHand() -> PatternDetectionResult? {
        guard canAnalyze, let winningTile = draft.winningTile else { return nil }
        return analyzeHand(forWinningTile: winningTile)
    }

    func analyzeHand(forWinningTile winningTile: MahjongTile) -> PatternDetectionResult? {
        let analyzer = HandPatternAnalyzer(
            draft: draft,
            winType: winType,
            selectedCircumstantialYaku: draft.selectedCircumstantialYaku,
            seatWindIndex: seatWindTileIndex(),
            roundWindIndex: roundWindTileIndex(),
            riichiYaku: draft.riichiYaku
        )
        return analyzer.analyze(winningTile: winningTile)
    }
    
    func seatWindTileIndex() -> Int {
        switch game.players[winnerIndex].name {
        case "东家": return MahjongTile.east.rawValue
        case "南家": return MahjongTile.south.rawValue
        case "西家": return MahjongTile.west.rawValue
        default: return MahjongTile.north.rawValue
        }
    }
    
    func roundWindTileIndex() -> Int {
        game.roundWindIndex == 0 ? MahjongTile.east.rawValue : MahjongTile.south.rawValue
    }
}
