//
//  ContentView.swift
//  richimaj
//
//  Created by linzihao on 2026/3/31.
//

import SwiftUI
import Combine
import UIKit

enum AppMode: String {
    case casual = "休闲模式"
    case competitive = "竞技模式"
}

struct CompetitiveConfig: Equatable {
    var turnTime: Int
    var reserveTime: Int
}

struct FormalScoringDraft: Identifiable, Hashable {
    let id = UUID()
    var winnerIndex: Int
    var winType: WinType
    var loserIndex: Int?
}

struct FormalWinnerEntry: Identifiable {
    let id = UUID()
    var winnerIndex: Int
    var hanInput: String
    var fuInput: String
    var yakumanMultiplier: Int = 0
}

struct HandPatternDraft {
    var activeSection: TileInputSection = .concealed
    var openMeldType: OpenMeldType = .chi
    var handCounts: [MahjongTile: Int] = [:]
    var openCounts: [MahjongTile: Int] = [:]
    var openMeldGroups: [OpenMeldGroup] = []
    var winningTile: MahjongTile? = nil
    var doraCount: Int = 0
    var redDoraCount: Int = 0
    var analysisResult: PatternDetectionResult? = nil
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
                game.declareRiichi(for: index)
            },
            canRiichi: canDeclareRiichi(for: index),
            compactLayout: compactLayout,
            timerDisplay: timerDisplay(for: index),
            showCompetitiveChrome: isCompetitiveMode,
            leftActionTitle: leftActionTitle(for: index),
            onLeftAction: leftAction(for: index),
            showStartButton: isCompetitiveMode && activeTurnIndex == index && !handTimerStarted,
            onStartTurn: isCompetitiveMode && activeTurnIndex == index && !handTimerStarted ? {
                startTurnTimer()
            } : nil,
            showFinishButton: isCompetitiveMode && activeTurnIndex == index && handTimerStarted,
            onFinishTurn: isCompetitiveMode && activeTurnIndex == index && handTimerStarted ? {
                finishCurrentTurn()
            } : nil
        )
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
    }
    
    func startTurnTimer() {
        guard competitiveConfig != nil else { return }
        handTimerStarted = true
    }

    func openFormalScoring(for winnerIndex: Int) {
        guard isCompetitiveMode else { return }
        handTimerStarted = false
        
        let draft: FormalScoringDraft
        if winnerIndex == activeTurnIndex {
            draft = FormalScoringDraft(
                winnerIndex: winnerIndex,
                winType: .tsumo,
                loserIndex: nil
            )
        } else {
            draft = FormalScoringDraft(
                winnerIndex: winnerIndex,
                winType: .ron,
                loserIndex: activeTurnIndex
            )
        }
        
        formalScoringDraft = draft
    }
    
    func finishCurrentTurn() {
        guard let competitiveConfig else { return }
        activeTurnIndex = (activeTurnIndex + 1) % game.players.count
        currentTurnMainTime = competitiveConfig.turnTime
        handTimerStarted = true
    }
    
    func tickCompetitiveTimer() {
        guard isCompetitiveMode else { return }
        guard !showingNewGameSetup, !showingDrawDecision else { return }
        guard !game.isMatchFinished else { return }
        guard handTimerStarted else { return }
        
        if currentTurnMainTime > 0 {
            currentTurnMainTime -= 1
        } else if reserveTimes[activeTurnIndex] > 0 {
            reserveTimes[activeTurnIndex] -= 1
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
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
    @State private var detectedYakuNames: [String] = []
    @State private var detectedNotes: [String] = []
    @State private var detectedYakumanMultiplier = 0
    
    private let hanOptions = Array(1...13)
    private let fuOptions = [20, 25, 30, 40, 50, 60, 70, 80, 90, 100, 110]

    var orderedRonWinnerIndices: [Int] {
        ronWinnerEntries.map(\.winnerIndex)
    }

    var needsSequentialRonPatternInput: Bool {
        winType == .ron && ronWinnerEntries.count > 1
    }

    var allRonPatternsCompleted: Bool {
        let winners = Set(orderedRonWinnerIndices)
        return !winners.isEmpty && winners.isSubset(of: completedPatternWinnerIndices)
    }

    var patternInputApplyButtonTitle: String {
        if needsSequentialRonPatternInput, let nextWinner = nextRonWinnerIndex(after: winnerIndex) {
            return "保存并前往\(game.players[nextWinner].name)"
        }
        return "应用到正式算分"
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
                    Button("牌型输入") {
                        showingPatternInput = true
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("拍照输入") {
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
                    Button("打开牌型输入页面") {
                        showingPatternInput = true
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("打开拍照输入页面") {
                        showingPhotoInput = true
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("当前最小版本按门前手设计：先录入 13 张手牌，再单独录入最后 1 张和牌。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text("拍照输入入口已预留，后续会接相机拍照识别并回填到正式算分。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("当前牌局状态") {
                VStack(alignment: .leading, spacing: 8) {
                    labelRow(title: "当前局", detail: game.roundText)
                    labelRow(title: "本场", detail: "\(game.honbaCount)")
                    labelRow(title: "立直棒", detail: "\(game.riichiStickCount)")
                    labelRow(title: "当前胡牌者身份", detail: currentWinnerIdentityText)
                }
            }
            
            if !detectedYakuNames.isEmpty || !detectedNotes.isEmpty {
                Section("牌型识别结果") {
                    if !detectedYakuNames.isEmpty {
                        labelRow(title: "识别役种", detail: detectedYakuNames.joined(separator: "、"))
                    }
                    ForEach(detectedNotes, id: \.self) { note in
                        Text(note)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if winType == .ron {
                if !multiRonPreviews.isEmpty {
                    Section("结算预览") {
                        ForEach(multiRonPreviews.indices, id: \.self) { index in
                            let preview = multiRonPreviews[index]
                            VStack(alignment: .leading, spacing: 6) {
                                Text(game.players[preview.winnerIndex].name)
                                    .font(.headline)
                                Text(preview.limitName ?? "番符：\(preview.han) 番 \(preview.fu) 符")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                Text("该家获得：\(preview.winnerGain - (index == 0 ? 0 : preview.riichiBonus)) 点")
                                    .font(.footnote)
                                Text("点炮者支付：\(preview.loserPayment ?? 0) 点")
                                    .font(.footnote)
                            }
                            .padding(.vertical, 4)
                        }
                        
                        labelRow(title: "点炮者总支付", detail: "\(multiRonTotalPayment) 点")
                    }
                }
            } else if let scorePreview = scorePreview {
                Section("结算预览") {
                    labelRow(
                        title: "番符",
                        detail: scorePreview.limitName ?? "\(scorePreview.han) 番 \(scorePreview.fu) 符"
                    )
                    
                    if scorePreview.winType == .ron {
                        labelRow(
                            title: "放铳支付",
                            detail: "\(scorePreview.loserPayment ?? 0) 点"
                        )
                    } else if scorePreview.isEastWin {
                        labelRow(
                            title: "每家支付",
                            detail: "\(scorePreview.nonDealerPayment ?? 0) 点"
                        )
                    } else {
                        labelRow(
                            title: "庄家支付",
                            detail: "\(scorePreview.dealerPayment ?? 0) 点"
                        )
                        labelRow(
                            title: "闲家各付",
                            detail: "\(scorePreview.nonDealerPayment ?? 0) 点"
                        )
                    }
                    
                    labelRow(
                        title: "胡牌者总收入",
                        detail: "\(scorePreview.winnerGain) 点"
                    )
                }
            }
            
            if !needsSequentialRonPatternInput || allRonPatternsCompleted {
                Section {
                    Button("确认结算") {
                        applyFormalSettlement()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(!canConfirmFormalScore)
                }
            }
            
            Section("说明") {
                Text("这是一版最小可用正式算分：手动输入番数和符数，再按庄闲、自摸/荣和、本场和立直棒自动结算。")
            }
        }
        .navigationTitle("正式算分")
        .onAppear {
            configureInitialState()
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
                    winnerIndex: winnerIndex,
                    winType: winType,
                    draft: currentPatternDraftBinding,
                    applyButtonTitle: patternInputApplyButtonTitle,
                    winnerSummaryText: patternInputWinnerSummaryText
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
                PhotoRecognitionView { result in
                    if let importedDraft = PhotoRecognitionImport.makeHandPatternDraft(from: result) {
                        if winType == .ron {
                            ronWinnerDrafts[winnerIndex] = importedDraft
                        } else {
                            handPatternDraft = importedDraft
                        }
                        detectedYakuNames = ["已回填拍照识别牌面"]
                        detectedNotes = result.notes + ["识别牌面已经回填到牌型输入草稿，可以继续打开牌型输入页手动微调。"]
                        showingPhotoInput = false
                        DispatchQueue.main.async {
                            showingPatternInput = true
                        }
                    } else {
                        detectedYakuNames = []
                        detectedNotes = result.notes + ["这次拍照结果还不足以完整回填到牌型输入草稿。"]
                        showingPhotoInput = false
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

    func applyPatternDetectionResult(_ result: PatternDetectionResult) {
        if winType == .ron {
            if let entryIndex = ronWinnerEntries.firstIndex(where: { $0.winnerIndex == winnerIndex }) {
                ronWinnerEntries[entryIndex].hanInput = "\(result.han)"
                ronWinnerEntries[entryIndex].fuInput = "\(result.fu)"
                ronWinnerEntries[entryIndex].yakumanMultiplier = result.yakumanMultiplier
            } else {
                ronWinnerEntries.append(
                    FormalWinnerEntry(
                        winnerIndex: winnerIndex,
                        hanInput: "\(result.han)",
                        fuInput: "\(result.fu)",
                        yakumanMultiplier: result.yakumanMultiplier
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
    
    var multiRonTotalPayment: Int {
        multiRonPreviews.reduce(0) { $0 + ($1.loserPayment ?? 0) }
    }
    
    var canConfirmFormalScore: Bool {
        if winType == .ron {
            if needsSequentialRonPatternInput && !allRonPatternsCompleted {
                return false
            }
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
            let labels = ronWinnerEntries.map { game.isEastPlayer($0.winnerIndex) ? "\(game.players[$0.winnerIndex].name)(庄)" : "\(game.players[$0.winnerIndex].name)(闲)" }
            return labels.joined(separator: "、")
        }
        return game.isEastPlayer(winnerIndex) ? "庄家" : "闲家"
    }
    
    func configureInitialState() {
        if let draft {
            winnerIndex = draft.winnerIndex
            winType = draft.winType
            loserIndex = draft.loserIndex ?? availableLoserIndices.first ?? 0
            ronWinnerEntries = [
                FormalWinnerEntry(winnerIndex: draft.winnerIndex, hanInput: "1", fuInput: "30")
            ]
        } else {
            winnerIndex = 0
            winType = .ron
            loserIndex = 1
            ronWinnerEntries = [
                FormalWinnerEntry(winnerIndex: 0, hanInput: "1", fuInput: "30")
            ]
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
                        ForEach(hanOptions, id: \.self) { han in
                            Text("\(han) 番").tag(String(han))
                        }
                    }
                    
                    Picker("符数", selection: $entry.fuInput) {
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
                FormalWinnerEntry(winnerIndex: index, hanInput: "1", fuInput: "30")
            )
            winnerIndex = index
        }
        fixLoserIfNeeded()
    }

    func loadCurrentPatternDraftIfNeeded() {
        if winType == .ron, ronWinnerDrafts[winnerIndex] == nil {
            ronWinnerDrafts[winnerIndex] = HandPatternDraft()
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
                loadCurrentPatternDraftIfNeeded()
                return
            }
        }
        showingPatternInput = false
    }
}

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

struct HandPatternInputView: View {
    @ObservedObject var game: GameState
    var winnerIndex: Int
    var winType: WinType
    @Binding var draft: HandPatternDraft
    var applyButtonTitle = "应用到正式算分"
    var winnerSummaryText: String? = nil
    var onApply: (PatternDetectionResult) -> Void
    
    @Environment(\.dismiss) private var dismiss

    var winnerHasRiichi: Bool {
        game.players.indices.contains(winnerIndex) && game.players[winnerIndex].isRiichi
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusSection
                
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
                
                if let analysisResult = draft.analysisResult {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("识别结果")
                            .font(.headline)
                        Text("番数：\(analysisResult.han) 番")
                        Text("符数：\(analysisResult.fu) 符")
                        Text("役种：\(analysisResult.yakuNames.joined(separator: "、"))")
                        ForEach(analysisResult.notes, id: \.self) { note in
                            Text(note)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.7))
                    .cornerRadius(14)
                }
                
                HStack(spacing: 12) {
                    Button("识别牌型") {
                        draft.analysisResult = analyzeHand()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAnalyze)
                    
                    Button(applyButtonTitle) {
                        if let analysisResult = draft.analysisResult {
                            onApply(analysisResult)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(draft.analysisResult == nil)
                }
            }
            .padding(16)
        }
        .background(Color(red: 0.96, green: 0.93, blue: 0.83).ignoresSafeArea())
        .navigationTitle("牌型输入")
        .onAppear {
            if winnerHasRiichi {
                draft.openMeldType = .concealedKan
            }
            sanitizeDraft()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭") {
                    dismiss()
                }
            }
        }
    }
    
    var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(winnerHasRiichi ? "当前最小版本支持：手牌 / 暗杠 / 胡牌 三块输入" : "当前最小版本支持：手牌 / 副露 / 胡牌 三块输入")
                .font(.headline)
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
                Picker(winnerHasRiichi ? "暗杠类型" : "副露类型", selection: $draft.openMeldType) {
                    ForEach(winnerHasRiichi ? [OpenMeldType.concealedKan] : OpenMeldType.allCases, id: \.id) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                
                Text(winnerHasRiichi ? "这里仅录入暗杠。暗杠会记入杠子张数，但识别时仍按门前清处理。" : "副露区域下，点一次牌会按所选类型直接加入整组副露。吃使用起始牌，例如点 3万 会加入 3-4-5万。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 10) {
                sectionSummaryCard(
                    title: "手牌",
                    countText: "\(totalHandCount) 张",
                    detailText: concealedKongCount > 0 ? "杠子 \(concealedKongCount) 组" : "未成杠",
                    isActive: draft.activeSection == .concealed
                )
                sectionSummaryCard(
                    title: winnerHasRiichi ? "暗杠" : "副露",
                    countText: "\(totalOpenCount) 张",
                    detailText: openKongCount > 0 ? "杠子 \(openKongCount) 组" : "未成杠",
                    isActive: draft.activeSection == .openMeld
                )
                sectionSummaryCard(
                    title: "胡牌",
                    countText: draft.winningTile?.label ?? "未选",
                    detailText: "最后选择",
                    isActive: draft.activeSection == .winning
                )
            }
            
            Text("总牌数：\(totalTileCount) / \(requiredTileCountBeforeWin)")
            Text("杠子数：\(totalKongCount) 组")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text("宝牌：\(draft.doraCount) 番，红宝牌：\(draft.redDoraCount) 番")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text("胡牌者：\(game.players[winnerIndex].name)，和牌方式：\(winType.rawValue)")
                .font(.footnote)
                .foregroundColor(.secondary)
            
            Button("清空输入") {
                draft = HandPatternDraft()
            }
            .font(.footnote)
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.white.opacity(0.7))
        .cornerRadius(14)
    }
    
    func sectionSummaryCard(title: String, countText: String, detailText: String, isActive: Bool) -> some View {
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
    }
    
    func tilePickerCard(_ tile: MahjongTile) -> some View {
        let totalCount = totalCount(for: tile)
        
        return VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .frame(height: 74)
                .overlay {
                    VStack(spacing: 2) {
                        remoteTileFace(tile, height: 48)
                        Text("x\(max(0, 4 - totalCount))")
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
            
            if totalTileCount == requiredTileCountBeforeWin || draft.winningTile == tile {
                Button(draft.winningTile == tile ? "已选和牌" : "设为和牌") {
                    setWinningTile(tile)
                }
                .font(.caption)
                .buttonStyle(.bordered)
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
                    draft.analysisResult = nil
                }
                .buttonStyle(.bordered)
                
                Button("+") {
                    onIncrease()
                    draft.analysisResult = nil
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
        draft.handCounts.values.filter { $0 == 4 }.count
    }
    
    var openKongCount: Int {
        draft.openCounts.values.filter { $0 == 4 }.count
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
    
    func handCount(for tile: MahjongTile) -> Int {
        draft.handCounts[tile, default: 0]
    }
    
    func openCount(for tile: MahjongTile) -> Int {
        draft.openCounts[tile, default: 0]
    }
    
    func totalCount(for tile: MahjongTile) -> Int {
        handCount(for: tile) + openCount(for: tile) + (draft.winningTile == tile ? 1 : 0)
    }
    
    func addTile(_ tile: MahjongTile) {
        switch draft.activeSection {
        case .concealed:
            addHandTile(tile)
        case .openMeld:
            addOpenTile(tile)
        case .winning:
            setWinningTile(tile)
        }
    }
    
    func removeTile(_ tile: MahjongTile) {
        switch draft.activeSection {
        case .concealed:
            removeHandTile(tile)
        case .openMeld:
            removeOpenTile(tile)
        case .winning:
            if draft.winningTile == tile {
                draft.winningTile = nil
                draft.analysisResult = nil
            }
        }
    }
    
    func addHandTile(_ tile: MahjongTile) {
        guard canAddTile(toConcealed: true, tile: tile) else { return }
        guard totalCount(for: tile) < 4 else { return }
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
        guard let tiles = tilesForOpenMeld(from: tile, type: draft.openMeldType) else { return }
        guard canAddOpenMeld(tiles) else { return }
        for meldTile in tiles {
            draft.openCounts[meldTile, default: 0] += 1
        }
        draft.openMeldGroups.append(OpenMeldGroup(type: draft.openMeldType, tiles: tiles))
        draft.analysisResult = nil
        updateActiveSectionForCurrentTileCount()
    }
    
    func removeOpenTile(_ tile: MahjongTile) {
        guard let tiles = tilesForOpenMeld(from: tile, type: draft.openMeldType) else { return }
        guard canRemoveOpenMeld(tiles) else { return }
        for meldTile in tiles {
            draft.openCounts[meldTile, default: 0] -= 1
            if draft.openCounts[meldTile] == 0 {
                draft.openCounts.removeValue(forKey: meldTile)
            }
        }
        if let groupIndex = draft.openMeldGroups.lastIndex(where: { $0.type == draft.openMeldType && $0.tiles == tiles }) {
            draft.openMeldGroups.remove(at: groupIndex)
        }
        draft.analysisResult = nil
        updateActiveSectionForCurrentTileCount()
    }
    
    func setWinningTile(_ tile: MahjongTile) {
        guard totalTileCount == requiredTileCountBeforeWin else { return }
        guard handCount(for: tile) + openCount(for: tile) + (draft.winningTile == tile ? 0 : 1) <= 4 else {
            return
        }
        draft.winningTile = tile
        draft.analysisResult = nil
    }

    func updateActiveSectionForCurrentTileCount() {
        if totalTileCount == requiredTileCountBeforeWin {
            draft.activeSection = .winning
        } else if draft.activeSection == .winning {
            draft.activeSection = .concealed
        }
    }
    
    func canAddTile(toConcealed: Bool, tile: MahjongTile) -> Bool {
        if totalCount(for: tile) >= 4 {
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
            projectedHandCounts.values.filter { $0 == 4 }.count +
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
        
        if let winningTile = draft.winningTile,
           handCount(for: winningTile) + openCount(for: winningTile) >= 4 {
            draft.winningTile = nil
        }
        
        draft.analysisResult = nil
    }
    
    func tilesForOpenMeld(from tile: MahjongTile, type: OpenMeldType) -> [MahjongTile]? {
        switch type {
        case .chi:
            guard let suitIndex = tile.suitIndex, let number = tile.number, number <= 7 else {
                return nil
            }
            let base = suitIndex * 9 + (number - 1)
            guard let second = MahjongTile(rawValue: base + 1),
                  let third = MahjongTile(rawValue: base + 2) else {
                return nil
            }
            return [tile, second, third]
            
        case .pon:
            return [tile, tile, tile]
            
        case .openKan, .concealedKan:
            return [tile, tile, tile, tile]
        }
    }
    
    func canAddOpenMeld(_ tiles: [MahjongTile]) -> Bool {
        let projectedHandCounts = draft.handCounts
        var projectedOpenCounts = draft.openCounts
        
        for tile in tiles {
            if handCount(for: tile) + openCount(for: tile) + (draft.winningTile == tile ? 1 : 0) >= 4 {
                return false
            }
            projectedOpenCounts[tile, default: 0] += 1
        }
        
        let projectedKongCount =
            projectedHandCounts.values.filter { $0 == 4 }.count +
            projectedOpenCounts.values.filter { $0 == 4 }.count
        let projectedTileCount =
            projectedHandCounts.values.reduce(0, +) +
            projectedOpenCounts.values.reduce(0, +)
        
        return projectedTileCount <= 13 + projectedKongCount
    }
    
    func canRemoveOpenMeld(_ tiles: [MahjongTile]) -> Bool {
        var tempCounts = draft.openCounts
        for tile in tiles {
            guard tempCounts[tile, default: 0] > 0 else { return false }
            tempCounts[tile, default: 0] -= 1
        }
        return true
    }
    
    func analyzeHand() -> PatternDetectionResult? {
        guard canAnalyze, let winningTile = draft.winningTile else { return nil }
        
        let fullCounts = combinedCounts(with: winningTile)
        let context = HandAnalysisContext(openMeldGroups: draft.openMeldGroups)
        guard let structuralCounts = structuralCountsForAnalysis(fullCounts, context: context) else {
            return PatternDetectionResult(
                han: 0,
                fu: 0,
                yakuNames: [],
                notes: ["当前副露结构和牌张数不一致，请检查吃/碰/杠录入。"]
            )
        }
        let hasOpenMelds = draft.openMeldGroups.contains { $0.type != .concealedKan }
        
        if !hasOpenMelds, let kokushiResult = kokushiDetectionResult(fullCounts: fullCounts, winningTile: winningTile) {
            return applyBonusHan(to: kokushiResult)
        }
        
        if totalKongCount == 4 {
            return applyBonusHan(to: PatternDetectionResult(
                han: 13,
                fu: 0,
                yakuNames: ["四杠子"],
                notes: [
                    "四杠子按役满处理。",
                    "当前最小版本对四杠子的其他复合役未继续叠加。"
                ],
                yakumanMultiplier: 1
            ))
        }
        
        if !hasOpenMelds && isSevenPairs(structuralCounts) {
            var yakuNames = ["七对子"]
            var han = 2
            let notes = ["七对子固定 25 符。", "这版牌型输入目前只按门前手识别。"]
            
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
                return PatternDetectionResult(
                    han: han,
                    fu: 25,
                    yakuNames: yakuNames,
                    notes: ["按常见算え役満口径，累计 13 番以上按役满处理。"] + notes
                )
            }
            return applyBonusHan(to: PatternDetectionResult(
                han: han,
                fu: 25,
                yakuNames: yakuNames,
                notes: notes
            ))
        }
        
        let candidates = standardHandCandidates(
            counts: structuralCounts,
            winningTile: winningTile.rawValue
        )
        guard !candidates.isEmpty else {
            return PatternDetectionResult(
                han: 0,
                fu: 0,
                yakuNames: [],
                notes: ["当前未识别为可和的标准牌型。"]
            )
        }
        
        let analyses = candidates.compactMap { candidate in
            analyzeCandidate(candidate, fullCounts: fullCounts, hasOpenMelds: hasOpenMelds, context: context)
        }
        
        guard let best = analyses.max(by: { lhs, rhs in
            if lhs.han == rhs.han {
                return lhs.fu < rhs.fu
            }
            return lhs.han < rhs.han
        }) else {
            return nil
        }
        
        return applyBonusHan(to: best)
    }

    func applyBonusHan(to result: PatternDetectionResult) -> PatternDetectionResult {
        let bonusHan = draft.doraCount + draft.redDoraCount
        guard bonusHan > 0 else {
            return result
        }
        
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
        counts.map { min($0, 3) }
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
    
    func standardHandCandidates(
        counts: [Int],
        winningTile: Int
    ) -> [StandardHandCandidate] {
        var candidates: [StandardHandCandidate] = []
        
        for pairIndex in counts.indices where counts[pairIndex] >= 2 {
            var remaining = counts
            remaining[pairIndex] -= 2
            var groups: [HandGroup] = []
            var allGroupSets: [[HandGroup]] = []
            buildGroups(counts: &remaining, current: &groups, results: &allGroupSets)
            
            for groupSet in allGroupSets {
                let possibleWaits = waitKinds(
                    pairTile: pairIndex,
                    groups: groupSet,
                    winningTile: winningTile
                )
                for wait in possibleWaits {
                    candidates.append(
                        StandardHandCandidate(
                            pairTile: pairIndex,
                            groups: groupSet,
                            waitKind: wait
                        )
                    )
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
        
        if winType == .tsumo && !hasOpenMelds {
            yakuNames.append("门前清自摸和")
            han += 1
        }
        
        if isTanyao(fullCounts) {
            yakuNames.append("断幺九")
            han += 1
        }
        
        let yakuhaiCount = yakuhaiHan(allGroups)
        if yakuhaiCount > 0 {
            for _ in 0..<yakuhaiCount {
                yakuNames.append("役牌")
            }
            han += yakuhaiCount
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
            return PatternDetectionResult(
                han: isSingleWait ? 26 : 13,
                fu: 0,
                yakuNames: [isSingleWait ? "四暗刻单骑" : "四暗刻"],
                notes: [isSingleWait ? "四暗刻单骑按双役满处理。" : "四暗刻按役满处理。"],
                yakumanMultiplier: isSingleWait ? 2 : 1
            )
        }
        
        if isDaisangen(allGroups) {
            return PatternDetectionResult(
                han: 13,
                fu: 0,
                yakuNames: ["大三元"],
                notes: ["大三元按役满处理。"],
                yakumanMultiplier: 1
            )
        }
        
        if isTsuuiisou(fullCounts) {
            return PatternDetectionResult(
                han: 13,
                fu: 0,
                yakuNames: ["字一色"],
                notes: ["字一色按役满处理。"],
                yakumanMultiplier: 1
            )
        }
        
        if isChinroutou(fullCounts) {
            return PatternDetectionResult(
                han: 13,
                fu: 0,
                yakuNames: ["清老头"],
                notes: ["清老头按役满处理。"],
                yakumanMultiplier: 1
            )
        }
        
        if isShousuushii(allGroups, pairTile: candidate.pairTile) {
            return PatternDetectionResult(
                han: 13,
                fu: 0,
                yakuNames: ["小四喜"],
                notes: ["小四喜按役满处理。"],
                yakumanMultiplier: 1
            )
        }
        
        if isDaisuushii(allGroups) {
            return PatternDetectionResult(
                han: 26,
                fu: 0,
                yakuNames: ["大四喜"],
                notes: ["大四喜按双役满处理。"],
                yakumanMultiplier: 2
            )
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
        
        guard !yakuNames.isEmpty else {
            return nil
        }
        
        let fu = calculateFu(candidate, hasOpenMelds: hasOpenMelds, context: context)
        var notes = [
            hasOpenMelds ? "当前副露版仍是简化识别，明暗刻与杠的符数建议回正式算分页手动复核。" : "当前最小版本只按门前手识别，未自动计入立直、一发、宝牌、里宝牌、杠宝牌。",
            "累计 13 番以上按常见算え役満口径处理。"
        ]
        
        if han >= 13 {
            notes.append("这手按累计役满口径结算。")
        }
        
        return PatternDetectionResult(
            han: han,
            fu: fu,
            yakuNames: yakuNames,
            notes: notes
        )
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
        let sequences = groups
            .filter { $0.kind == .sequence }
            .map { $0.tiles }
        var seen: [[Int]: Int] = [:]
        for sequence in sequences {
            seen[sequence, default: 0] += 1
        }
        return seen.values.contains(where: { $0 >= 2 })
    }
    
    func isToitoi(_ groups: [HandGroup]) -> Bool {
        groups.allSatisfy { $0.kind == .triplet }
    }
    
    func isSanshokuDoujun(_ groups: [HandGroup]) -> Bool {
        let starts = groups
            .filter { $0.kind == .sequence }
            .compactMap { group -> (Int, Int)? in
                guard let tile = MahjongTile(rawValue: group.tiles[0]),
                      let suit = tile.suitIndex,
                      let number = tile.number else { return nil }
                return (number, suit)
            }
        
        for number in 1...7 {
            let suits = starts.filter { $0.0 == number }.map { $0.1 }
            if Set(suits) == Set([0, 1, 2]) {
                return true
            }
        }
        return false
    }
    
    func isIttsu(_ groups: [HandGroup]) -> Bool {
        let sequences = groups.filter { $0.kind == .sequence }
        for suit in 0...2 {
            let needed = Set([1, 4, 7])
            let starts = Set(sequences.compactMap { group -> Int? in
                guard let tile = MahjongTile(rawValue: group.tiles[0]),
                      tile.suitIndex == suit else { return nil }
                return tile.number
            })
            if needed.isSubset(of: starts) {
                return true
            }
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
            if tile.isTerminalOrHonor {
                return false
            }
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
            if !tile.isTerminalOrHonor {
                return false
            }
        }
        return true
    }
    
    func yakuhaiHan(_ groups: [HandGroup]) -> Int {
        groups.reduce(0) { partialResult, group in
            guard group.kind == .triplet else { return partialResult }
            let tileIndex = group.tiles[0]
            return partialResult + valueTileHan(for: tileIndex)
        }
    }
    
    func valueTileHan(for tileIndex: Int) -> Int {
        guard let tile = MahjongTile(rawValue: tileIndex) else { return 0 }
        
        switch tile {
        case .white, .green, .red:
            return 1
        case .east, .south, .west, .north:
            var han = 0
            if seatWindTileIndex() == tileIndex {
                han += 1
            }
            if roundWindTileIndex() == tileIndex {
                han += 1
            }
            return han
        default:
            return 0
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
    
    func isConcealedKongTile(_ tileIndex: Int) -> Bool {
        guard let tile = MahjongTile(rawValue: tileIndex) else { return false }
        return draft.handCounts[tile, default: 0] == 4
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
        
        guard yaochuIndices.allSatisfy({ fullCounts[$0] >= 1 }) else {
            return nil
        }
        
        let pairCount = yaochuIndices.filter { fullCounts[$0] >= 2 }.count
        guard pairCount == 1 else {
            return nil
        }
        
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
}
