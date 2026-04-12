# 模型训练与导出

## 目标

项目包含两类模型：

1. 单牌检测框模型
2. 单牌分类模型

## 标注

### detector 标注

- 工具：`labelme`
- 目标：只标“哪里有一张牌”
- 标注对象：三区切图后的区域图或原图切区后的牌框

### classifier 标注

- 工具：`labelme`
- 目标：单牌分类标签
- 标签格式：
  - `1m..9m`
  - `1p..9p`
  - `1s..9s`
  - `dong nan xi bei bai fa zhong`

## detector 训练

训练目录：
- [/Users/lin/Desktop/majproj/training/mahjong_tile_detector](/Users/lin/Desktop/majproj/training/mahjong_tile_detector)

当前 app 实际部署的是：
- YOLO11 ONNX detector

原因：
- YOLO11 detector 走 CoreML 导出链不稳定
- ONNX Runtime iOS 更适合当前 detector 部署

## classifier 训练

训练目录：
- [/Users/lin/Desktop/majproj/training/mahjong_tile_classifier](/Users/lin/Desktop/majproj/training/mahjong_tile_classifier)

当前结构：
- 34 类主模型
- `man` 子模型
- `pin` 子模型
- `sou` 子模型
- `honor` 子模型

## 数据构建

单牌分类训练集来自：
- detector 裁出来的单牌图
- 用户在 `labelme` 中修正后的标签

常见增强：
- 原图
- 旋转 180°

## CoreML 导出注意点

分类模型导出时必须与训练输入保持一致：

- `scale = 1/255.0`
- `color_layout = RGB`
- 当前已改为 `FLOAT32`，避免 iOS 端出现 `inf/-inf`

导出脚本：
- [export_coreml.py](/Users/lin/Desktop/majproj/training/mahjong_tile_classifier/scripts/export_coreml.py)

## 当前问题边界

### detector
- 某些区域仍可能漏检或多检
- `winning` 区通常最稳定

### classifier
- 数值溢出问题已修
- 当前主要问题转为正常识别误差，而不是运行时崩坏

## 推荐训练流程

1. 新拍原图
2. 用 detector 批量切出单牌
3. 用相似度匹配先自动打标签
4. 人工复核修正
5. 合并进训练集
6. 重新训练主模型与子模型
7. 导出 CoreML
8. 替换 app bundle 中模型
