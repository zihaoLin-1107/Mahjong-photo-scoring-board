import Foundation
import Combine
import UIKit

final class PhotoRecognitionViewModel: ObservableObject {
    @Published var request = PhotoRecognitionRequest()
    @Published var isRecognizing = false
    @Published var result: PhotoRecognitionResult?
    @Published var errorMessage: String?
    @Published var hasSelectedLocalImage = false
    
    private let service: any PhotoRecognitionService
    
    init(service: (any PhotoRecognitionService)? = nil) {
        if let service {
            self.service = service
        } else if Self.isRunningInPreviews {
            self.service = MockPhotoRecognitionService()
        } else {
            self.service = LocalVisionPhotoRecognitionService()
        }
    }

    private static var isRunningInPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    func recognize() {
        guard !isRecognizing else { return }
        isRecognizing = true
        errorMessage = nil
        
        let request = self.request
        let service = self.service
        Task {
            do {
                let result = try await service.recognize(request: request)
                await MainActor.run {
                    self.result = result
                    self.isRecognizing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? "识别失败。"
                    self.isRecognizing = false
                }
            }
        }
    }
    
    func loadSample() {
        request.source = .sample
        request.handPatternHint = .unknown
        request.note = "示例测试照片"
        if let image = UIImage(named: "photo_sample_wechat"),
           let data = image.jpegData(compressionQuality: 0.95) {
            request.imageData = data
            hasSelectedLocalImage = true
        } else {
            request.imageData = nil
            hasSelectedLocalImage = false
        }
        errorMessage = nil
        result = nil
    }
    
    func updateImageData(_ data: Data?) {
        request.imageData = data
        hasSelectedLocalImage = data != nil
        if data != nil && request.source == .sample {
            request.source = .photoLibrary
        }
        result = nil
        errorMessage = nil
    }
    
    func reset() {
        request = PhotoRecognitionRequest()
        isRecognizing = false
        result = nil
        errorMessage = nil
        hasSelectedLocalImage = false
    }
}
