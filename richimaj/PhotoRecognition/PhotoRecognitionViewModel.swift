import Foundation
import Combine

final class PhotoRecognitionViewModel: ObservableObject {
    @Published var request = PhotoRecognitionRequest()
    @Published var isRecognizing = false
    @Published var result: PhotoRecognitionResult?
    @Published var errorMessage: String?
    @Published var hasSelectedLocalImage = false
    
    private let service: any PhotoRecognitionService
    
    init(service: any PhotoRecognitionService = LocalVisionPhotoRecognitionService()) {
        self.service = service
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
        request.handPatternHint = .standard
        request.note = "示例手牌"
        request.imageData = nil
        hasSelectedLocalImage = false
        errorMessage = nil
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
