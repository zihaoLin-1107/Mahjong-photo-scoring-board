# richimaj

立直麻将记分与拍照录入应用。

当前项目包含两条主线：

- 记分与结算：休闲模式、竞技模式、正式算分页、役种/符数/点数计算
- 拍照输入：从相机或相册导入牌面，自动识别后进入确认/微调页面，再进入正式算分

## 主要功能

- 休闲模式记分
- 竞技模式记分、立直棒、本场、鸣牌优先级与倒计时
- 手动录入牌面
- 拍照识别牌面并自动回填
- 正式算分页展示役种、符数、点数与结算

## 技术栈

- SwiftUI
- AVFoundation
- Vision / CoreML
- ONNX Runtime iOS
- Python 训练与模型导出脚本

## 仓库结构

- [/Users/lin/Desktop/majproj/richimaj/richimaj](/Users/lin/Desktop/majproj/richimaj/richimaj)：iOS App 源码
- [/Users/lin/Desktop/majproj/richimaj/Vendor](/Users/lin/Desktop/majproj/richimaj/Vendor)：本地三方依赖
- [/Users/lin/Desktop/majproj/training/mahjong_tile_detector](/Users/lin/Desktop/majproj/training/mahjong_tile_detector)：单牌检测框训练与实验
- [/Users/lin/Desktop/majproj/training/mahjong_tile_classifier](/Users/lin/Desktop/majproj/training/mahjong_tile_classifier)：单牌分类训练与导出
- [/Users/lin/Desktop/majproj/richimaj/docs](/Users/lin/Desktop/majproj/richimaj/docs)：项目文档

## 运行

1. 用 Xcode 打开 [richimaj.xcodeproj](/Users/lin/Desktop/majproj/richimaj/richimaj.xcodeproj)
2. 选择 `richimaj` scheme
3. 在模拟器或真机运行

当前 app bundle 中模型分为两类：

- detector：ONNX
- classifier：CoreML

## 文档

- [架构说明](/Users/lin/Desktop/majproj/richimaj/docs/architecture.md)
- [拍照识别链路](/Users/lin/Desktop/majproj/richimaj/docs/photo-recognition.md)
- [模型训练与导出](/Users/lin/Desktop/majproj/richimaj/docs/training.md)
- [算番与竞技规则实现](/Users/lin/Desktop/majproj/richimaj/docs/scoring-rules.md)

## 当前实现口径

- 拍照输入不是直接算番，而是先自动填牌
- 自动识别后会进入确认/微调页面
- 只有高置信度牌会自动回填，低置信度牌留给用户手动补
- 正式算分基于确认后的牌面草稿进行
