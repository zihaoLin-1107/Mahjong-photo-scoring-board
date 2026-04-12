# 架构说明

## 总体结构

项目分为四层：

1. 交互层
- 主要入口与页面流转
- 休闲模式 / 竞技模式 / 拍照识别 / 正式算分

2. 领域层
- 手牌草稿、玩家状态、场况、本场、立直棒、役种与番数计算

3. 识别层
- 图片裁切
- 单牌检测框
- 单牌分类
- 识别结果后处理与回填

4. 训练层
- detector 数据处理、训练、导出
- classifier 数据处理、训练、CoreML 导出

## 关键源码

### 页面与状态

- [ContentView.swift](/Users/lin/Desktop/majproj/richimaj/richimaj/ContentView.swift)
- [GameState.swift](/Users/lin/Desktop/majproj/richimaj/richimaj/GameState.swift)
- [PlayerCardView.swift](/Users/lin/Desktop/majproj/richimaj/richimaj/PlayerCardView.swift)
- [richimajApp.swift](/Users/lin/Desktop/majproj/richimaj/richimaj/richimajApp.swift)

### 胡牌分析与规则

- [HandPatternAnalyzer.swift](/Users/lin/Desktop/majproj/richimaj/richimaj/HandPatternAnalyzer.swift)
- [MultipleRonRule.swift](/Users/lin/Desktop/majproj/richimaj/richimaj/MultipleRonRule.swift)

### 拍照识别

- [PhotoRecognitionView.swift](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/PhotoRecognitionView.swift)
- [PhotoRecognitionImport.swift](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/PhotoRecognitionImport.swift)
- [LocalVisionPhotoRecognitionService.swift](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/LocalVisionPhotoRecognitionService.swift)
- [PhotoRecognitionSegmentation.swift](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/PhotoRecognitionSegmentation.swift)
- [TileDetector.swift](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/TileDetector.swift)
- [SingleTileClassifier.swift](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/SingleTileClassifier.swift)

## 数据流

### 手动录入

`用户录牌 -> HandPatternDraft -> HandPatternAnalyzer -> 正式算分结果`

### 拍照录入

`相机/相册 -> 区域裁切 -> detector -> 分类器 -> 后处理 -> HandPatternDraft -> 确认/微调 -> HandPatternAnalyzer -> 正式算分结果`

## 模型部署结构

### detector

- 形式：YOLO11 ONNX
- 运行方式：ONNX Runtime iOS
- 作用：在三区域图内输出单牌框

### classifier

- 形式：CoreML
- 结构：
  - 34 类主模型
  - `man` 子模型
  - `pin` 子模型
  - `sou` 子模型
  - `honor` 子模型

## 设计原则

- 拍照识别只负责“自动填牌”，不直接替代正式算分
- 规则判断只基于最终确认后的牌面草稿
- 竞技模式与休闲模式共用大部分算番逻辑
- 模型链允许低置信度留空，优先保证可修正性
