import SwiftUI
import PhotosUI
import UIKit

struct PhotoRecognitionView: View {
    @StateObject private var viewModel: PhotoRecognitionViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCameraPicker = false
    @State private var autoForwardedResultID: UUID?
    var context: PhotoRecognitionContext? = nil
    var onConfirmResult: ((PhotoRecognitionResult) -> Void)? = nil
    
    init(
        viewModel: PhotoRecognitionViewModel = PhotoRecognitionViewModel(),
        context: PhotoRecognitionContext? = nil,
        onConfirmResult: ((PhotoRecognitionResult) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.context = context
        self.onConfirmResult = onConfirmResult
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                requestSection
                actionSection
                resultSection
            }
            .padding(16)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.94, blue: 0.86),
                    Color(red: 0.94, green: 0.91, blue: 0.80)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("拍照识别")
        .fullScreenCover(isPresented: $showingCameraPicker) {
            CameraImagePicker { data in
                viewModel.updateImageData(data)
            }
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                let data = try? await newValue.loadTransferable(type: Data.self)
                await MainActor.run {
                    viewModel.updateImageData(data)
                }
            }
        }
        .onChange(of: viewModel.result?.id) { _, newValue in
            guard
                viewModel.request.source == .camera || viewModel.request.source == .photoLibrary,
                let onConfirmResult,
                let result = viewModel.result,
                let resultID = newValue,
                autoForwardedResultID != resultID
            else { return }
            autoForwardedResultID = resultID
            onConfirmResult(result)
        }
    }

    var selectedPreviewImage: UIImage? {
        guard let data = viewModel.request.imageData else { return nil }
        return UIImage(data: data)
    }
    
    var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("拍照识别")
                .font(.largeTitle)
                .bold()
            Text("目标是从整张照片里拆出手牌、胡牌和副露，再回填到现有算分流程。")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
    
    var requestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("识别请求")
            
            Picker("来源", selection: $viewModel.request.source) {
                ForEach(PhotoRecognitionSource.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.segmented)
            
            if viewModel.request.source == .photoLibrary {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text(viewModel.hasSelectedLocalImage ? "已选择本地图像" : "从相册选择图片")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else if viewModel.request.source == .camera {
                Button(viewModel.hasSelectedLocalImage ? "重新拍照" : "打开相机拍照") {
                    showingCameraPicker = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                
                if !UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Text("当前设备没有可用相机，建议先用相册图片测试本地识别流程。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else if viewModel.request.source == .sample {
                Button(viewModel.hasSelectedLocalImage ? "重新载入示例照片" : "载入示例测试照片") {
                    selectedPhotoItem = nil
                    viewModel.loadSample()
                }
                .buttonStyle(.borderedProminent)
            }
            
            TextField("备注，例如：门前手 / 七对子 / 国士无双", text: $viewModel.request.note)
                .textFieldStyle(.roundedBorder)
            
            if viewModel.hasSelectedLocalImage {
                Text("已载入本地图像，开始识别时会优先走设备本地 Vision 分析。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if let previewImage = selectedPreviewImage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.request.source == .sample ? "测试照片预览" : "当前图片预览")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.78))
        .cornerRadius(16)
    }
    
    var actionSection: some View {
        HStack(spacing: 12) {
            Button("载入示例") {
                selectedPhotoItem = nil
                viewModel.loadSample()
            }
            .buttonStyle(.bordered)
            
            Button(viewModel.isRecognizing ? "识别中..." : "开始识别") {
                viewModel.recognize()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isRecognizing)
            
            Button("重置") {
                viewModel.reset()
            }
            .buttonStyle(.bordered)
        }
    }
    
    @ViewBuilder
    var resultSection: some View {
        if let errorMessage = viewModel.errorMessage {
            infoCard(title: "错误", content: errorMessage)
        }
        
        if let result = viewModel.result {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("识别结果")
                if let context {
                    resultSummaryCard(result: result, context: context)
                }

                postProcessStatusCard(result: result)

                if !result.regionResults.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("三区域裁剪调试")
                        ForEach(result.regionResults) { region in
                            regionDebugCard(region)
                        }
                    }
                }

                ForEach(result.tileGroups) { group in
                    tileGroupCard(group)
                }
                
                if !result.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("说明")
                            .font(.headline)
                        ForEach(result.notes, id: \.self) { note in
                            Text(note)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.78))
                    .cornerRadius(14)
                }

                if let onConfirmResult {
                    Button(result.isStructurallyValid ? "进入确认/微调" : "继续手动修正") {
                        onConfirmResult(result)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            infoCard(
                title: "结果预览",
                content: "先选择拍照、相册或示例，再点“开始识别”。识别后会按手牌、副露、胡牌三块区域展示麻将牌。"
            )
        }
    }
    
    func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
    }
    
    func infoCard(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(content)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.white.opacity(0.78))
        .cornerRadius(14)
    }
    
    func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .bold()
        }
    }
    
    func tileCard(_ tile: PhotoTileToken) -> some View {
        VStack(spacing: 2) {
            photoTileFace(tile)
                .frame(height: 58)
            Text(tile.subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 44, height: 82)
        .background(Color.white)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.18), lineWidth: 1)
        }
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }

    func tileGroupCard(_ group: PhotoTileGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title)
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(group.tiles) { tile in
                        tileCard(tile)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.78))
        .cornerRadius(14)
    }

    func regionDebugCard(_ region: PhotoRecognitionRegionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(region.regionTitle)
                    .font(.headline)
                Spacer()
                Text("识别 \(region.tileCount) 张")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let data = region.previewImageData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.16), lineWidth: 1)
                    )
            }

            if region.tiles.isEmpty {
                Text("当前区域还没有识别出稳定的牌。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(region.tiles) { tile in
                            tileCard(tile)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.78))
        .cornerRadius(14)
    }

    func resultSummaryCard(result: PhotoRecognitionResult, context: PhotoRecognitionContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                compactMetric(title: "当前局", detail: context.roundText)
                compactMetric(title: "本场", detail: "\(context.honbaCount)")
                compactMetric(title: "立直棒", detail: "\(context.riichiStickCount)")
                compactMetric(title: "胡牌者", detail: context.winnerIdentity)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("役种识别")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(result.suggestedPattern.rawValue)
                    .font(.headline)
                    .bold()
                Text("共识别 \(result.totalTileCount) 张牌 · 置信度 \(String(format: "%.0f%%", result.confidence * 100))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.white.opacity(0.78))
        .cornerRadius(14)
    }

    @ViewBuilder
    func postProcessStatusCard(result: PhotoRecognitionResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("后处理状态")
                    .font(.headline)
                Spacer()
                if let onConfirmResult, !result.isStructurallyValid {
                    Button("结构待修正") {
                        onConfirmResult(result)
                    }
                    .font(.caption)
                    .bold()
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.14))
                    .cornerRadius(999)
                    .buttonStyle(.plain)
                } else {
                    Text(result.isStructurallyValid ? "结构合理" : "结构待修正")
                        .font(.caption)
                        .bold()
                        .foregroundColor(result.isStructurallyValid ? Color.green : Color.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background((result.isStructurallyValid ? Color.green : Color.orange).opacity(0.14))
                        .cornerRadius(999)
                }
            }

            if result.postProcessWarnings.isEmpty {
                Text("当前三块区域没有触发额外约束修正。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(result.postProcessWarnings, id: \.self) { warning in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 2)
                        Text(warning)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.78))
        .cornerRadius(14)
    }

    func compactMetric(title: String, detail: String) -> some View {
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

    @ViewBuilder
    func photoTileFace(_ tile: PhotoTileToken) -> some View {
        if let assetName = tileAssetName(for: tile), UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFit()
        } else {
            Text(tile.displayName)
                .font(.headline)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func tileAssetName(for tile: PhotoTileToken) -> String? {
        switch tile.suit {
        case .man:
            guard let rank = tile.rank else { return nil }
            return "mahjong_man\(rank)"
        case .pin:
            guard let rank = tile.rank else { return nil }
            return "mahjong_pin\(rank)"
        case .sou:
            guard let rank = tile.rank else { return nil }
            return "mahjong_sou\(rank)"
        case .honor:
            switch tile.honorName {
            case "东": return "mahjong_east"
            case "南": return "mahjong_south"
            case "西": return "mahjong_west"
            case "北": return "mahjong_north"
            case "白": return "mahjong_white"
            case "发": return "mahjong_green"
            case "中": return "mahjong_red"
            default: return nil
            }
        }
    }
}
