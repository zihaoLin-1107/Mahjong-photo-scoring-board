# 拍照识别链路

## 目标

把相机或相册中的牌面图转换成可编辑的牌面草稿。

## 当前流程

1. 获取图片
- 来源：
  - 相机拍照
  - 相册选图

2. 预处理与板面裁切
- 统一方向
- 裁到预览取景板面区域

3. 固定三区切割
- `hand`
- `openMelds`
- `winning`

当前引导参数定义在：
- [PhotoCaptureGuideLayout.swift](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/PhotoCaptureGuideLayout.swift)

4. detector 出框
- 在三区域图内检测单牌框
- 当前 app 使用 ONNX detector：
  - [MahjongTileDetector.onnx](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/MahjongTileDetector.onnx)

5. `winning` 参考尺寸过滤
- 如果胡牌区检测到牌
- 取胡牌区最佳框为参考
- 对三区候选框做宽松尺寸过滤
- 目的是剔除明显过小或过大的噪音框

过滤实现：
- [LocalVisionPhotoRecognitionService.swift](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/LocalVisionPhotoRecognitionService.swift)

6. 单牌裁图
- 按 detector 框在各自区域中裁出单牌图

7. 单牌分类

### 7.1 主模型

- 34 类主模型先跑
- 输出 34 类概率

### 7.2 四大类聚合

不是独立的 4 类模型，而是用 34 类主模型 softmax 概率按组求和：

- `万 = man1...man9`
- `饼 = pin1...pin9`
- `条 = sou1...sou9`
- `字 = east + south + west + north + white + green + red`

### 7.3 子模型细分

根据四大类最高组，进入对应子模型：

- `man`
- `pin`
- `sou`
- `honor`

实现位置：
- [SingleTileClassifier.swift](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/SingleTileClassifier.swift)

8. 低置信度重试

如果最终 top-1 置信度 `< 0.90`：
- 会对 5 个变体图再次跑完整层级链
- 取最高置信度结果
- 如果 5 次后最高仍 `< 0.90`
- 不自动回填，留给用户手动补

当前 5 个变体：
- 旋转 180°
- 内裁 4%
- 内裁 8%
- 四周加 6% 白边
- 旋转 180° 后再加 6% 白边

9. 自动回填
- 高置信度牌自动回填到草稿
- 低置信度牌留空
- 识别后自动进入确认/微调页面

## 失败口径

如果检测/分类不稳定：
- 不强制假填
- 用户仍可以进入确认/微调页
- 手动补录缺失牌

## 当前模型文件

### detector
- [MahjongTileDetector.onnx](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/MahjongTileDetector.onnx)

### classifier
- [MahjongTileClassifier34.mlpackage](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/MahjongTileClassifier34.mlpackage)
- [MahjongTileClassifierMan.mlpackage](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/MahjongTileClassifierMan.mlpackage)
- [MahjongTileClassifierPin.mlpackage](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/MahjongTileClassifierPin.mlpackage)
- [MahjongTileClassifierSou.mlpackage](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/MahjongTileClassifierSou.mlpackage)
- [MahjongTileClassifierHonor.mlpackage](/Users/lin/Desktop/majproj/richimaj/richimaj/PhotoRecognition/MahjongTileClassifierHonor.mlpackage)

## 调试重点

- 看三区切图是否正确
- 看 detector 每区候选框数量
- 看 `winning` 区是否能提供参考框
- 看 34 类主模型输出是否正常
- 看子模型是否和大类路由一致
