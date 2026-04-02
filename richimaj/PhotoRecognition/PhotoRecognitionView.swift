import SwiftUI
import PhotosUI
import UIKit

struct PhotoRecognitionView: View {
    @StateObject private var viewModel: PhotoRecognitionViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCameraPicker = false
    var onConfirmResult: ((PhotoRecognitionResult) -> Void)? = nil
    
    init(
        viewModel: PhotoRecognitionViewModel = PhotoRecognitionViewModel(),
        onConfirmResult: ((PhotoRecognitionResult) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
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
        .sheet(isPresented: $showingCameraPicker) {
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
    }
    
    var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("拍照识别骨架")
                .font(.largeTitle)
                .bold()
            Text("这里先放独立识别流程，不干扰主记分和正式算分。后续把真实 Vision / 拍照接进来时，只替换服务层即可。")
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
            }
            
            Picker("牌型提示", selection: $viewModel.request.handPatternHint) {
                ForEach(PhotoHandPatternSuggestion.allCases) { pattern in
                    Text(pattern.rawValue).tag(pattern)
                }
            }
            .pickerStyle(.menu)
            
            TextField("备注，例如：门前手 / 七对子 / 国士无双", text: $viewModel.request.note)
                .textFieldStyle(.roundedBorder)
            
            if viewModel.hasSelectedLocalImage {
                Text("已载入本地图像，开始识别时会优先走设备本地 Vision 分析。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
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
                
                infoRow(title: "建议牌型", value: result.suggestedPattern.rawValue)
                infoRow(title: "置信度", value: String(format: "%.0f%%", result.confidence * 100))
                infoRow(title: "总牌数", value: "\(result.totalTileCount)")
                infoRow(title: "裁切牌面数", value: "\(result.croppedTileCount)")
                
                ForEach(result.tileGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(group.tiles) { tile in
                                    tileChip(tile)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.78))
                    .cornerRadius(14)
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
                    Button("确认并返回算分") {
                        onConfirmResult(result)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            infoCard(
                title: "结果预览",
                content: "先选一个来源，再点“开始识别”。现在这里是 mock 流程，不影响主记分板。"
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
    
    func tileChip(_ tile: PhotoTileToken) -> some View {
        VStack(spacing: 4) {
            Text(tile.displayName)
                .font(.headline)
            Text(tile.subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 58)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(red: 0.99, green: 0.98, blue: 0.95))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        }
        .cornerRadius(10)
    }
}

#Preview {
    NavigationStack {
        PhotoRecognitionView()
    }
}
