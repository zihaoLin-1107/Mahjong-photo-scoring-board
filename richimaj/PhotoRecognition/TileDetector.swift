import Foundation
import Vision
import CoreML
import CoreGraphics
import OnnxRuntimeBindings

struct TileDetection: Sendable {
    var boundingBox: CGRect
    var confidence: Double
}

protocol TileDetector: Sendable {
    func detectTiles(in cgImage: CGImage) -> [TileDetection]
}

struct VisionRectangleTileDetector: TileDetector {
    func detectTiles(in cgImage: CGImage) -> [TileDetection] {
        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.minimumAspectRatio = 0.2
        rectangleRequest.maximumAspectRatio = 0.9
        rectangleRequest.minimumSize = 0.02
        rectangleRequest.maximumObservations = 30

        let imageHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? imageHandler.perform([rectangleRequest])

        return (rectangleRequest.results ?? [])
            .map {
                TileDetection(
                    boundingBox: $0.boundingBox,
                    confidence: 1.0
                )
            }
            .sorted { lhs, rhs in
                let yDifference = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                if yDifference > 0.08 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.midX < rhs.boundingBox.midX
            }
    }
}

struct CoreMLObjectTileDetector: TileDetector {
    private let onnx = ONNXObjectTileDetector()

    func detectTiles(in cgImage: CGImage) -> [TileDetection] {
        let onnxDetections = onnx.detectTiles(in: cgImage)
        if !onnxDetections.isEmpty {
            return onnxDetections
        }

        guard let visionModel = Self.loadVisionModel(named: "MahjongTileDetector.mlpackage") else {
            return []
        }

        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results as? [VNRecognizedObjectObservation],
              !observations.isEmpty else {
            return []
        }

        return observations
            .map { observation in
                TileDetection(
                    boundingBox: observation.boundingBox,
                    confidence: Double(observation.confidence)
                )
            }
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                let yDifference = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                if yDifference > 0.08 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.midX < rhs.boundingBox.midX
            }
    }

    private static func loadVisionModel(named packageName: String) -> VNCoreMLModel? {
        if let cached = ModelCache.shared.visionModels[packageName] {
            return cached
        }

        let bundle = Bundle.main
        let candidates =
            (bundle.urls(forResourcesWithExtension: "mlpackage", subdirectory: nil) ?? []) +
            (bundle.urls(forResourcesWithExtension: "mlpackage", subdirectory: "PhotoRecognition") ?? [])
        guard let packageURL = candidates.first(where: { $0.lastPathComponent == packageName }) else {
            return nil
        }

        guard
            let compiledURL = try? MLModel.compileModel(at: packageURL),
            let model = try? MLModel(contentsOf: compiledURL),
            let visionModel = try? VNCoreMLModel(for: model)
        else {
            return nil
        }

        ModelCache.shared.visionModels[packageName] = visionModel
        return visionModel
    }

    private final class ModelCache: @unchecked Sendable {
        static let shared = ModelCache()
        var visionModels: [String: VNCoreMLModel] = [:]
    }
}

struct ONNXObjectTileDetector: TileDetector {
    private let inputSize = 640
    private let confidenceThreshold: Float = 0.25
    private let iouThreshold: CGFloat = 0.45
    private let maxDetections = 30

    func detectTiles(in cgImage: CGImage) -> [TileDetection] {
        guard let runtime = Runtime.shared else {
            NSLog("ONNX detector runtime unavailable: %@", Runtime.lastError ?? "unknown")
            return []
        }

        guard let prepared = prepareInput(from: cgImage) else {
            NSLog("ONNX detector prepareInput failed")
            return []
        }

        do {
            let inputData = NSMutableData(bytes: prepared.tensor, length: prepared.tensor.count * MemoryLayout<Float>.size)
            let inputValue = try ORTValue(
                tensorData: inputData,
                elementType: ORTTensorElementDataType.float,
                shape: [1, 3, NSNumber(value: inputSize), NSNumber(value: inputSize)]
            )

            let outputs = try runtime.session.run(
                withInputs: [runtime.inputName: inputValue],
                outputNames: [runtime.outputName],
                runOptions: nil
            )

            guard let outputValue = outputs[runtime.outputName] else {
                return []
            }

            let tensorData = try outputValue.tensorData()
            let shapeInfo = try outputValue.tensorTypeAndShapeInfo()

            let floats = Data(referencing: tensorData).withUnsafeBytes { rawBuffer in
                Array(rawBuffer.bindMemory(to: Float.self))
            }

            let shape = shapeInfo.shape.compactMap { $0.intValue }
            let detections = decodeOutput(
                floats,
                shape: shape,
                originalSize: CGSize(width: cgImage.width, height: cgImage.height),
                prepared: prepared
            )

            NSLog(
                "ONNX detector shape=%@ rawDetections=%d",
                shape.map(String.init).joined(separator: ","),
                detections.count
            )
            return nms(detections)
        } catch {
            NSLog("ONNX detector inference failed: %@", String(describing: error))
            return []
        }
    }

    private func prepareInput(from cgImage: CGImage) -> PreparedInput? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let scale = min(CGFloat(inputSize) / CGFloat(width), CGFloat(inputSize) / CGFloat(height))
        let resizedWidth = CGFloat(width) * scale
        let resizedHeight = CGFloat(height) * scale
        let padX = (CGFloat(inputSize) - resizedWidth) / 2
        let padY = (CGFloat(inputSize) - resizedHeight) / 2

        let bytesPerPixel = 4
        let bytesPerRow = inputSize * bytesPerPixel
        var rgba = [UInt8](repeating: 114, count: inputSize * inputSize * bytesPerPixel)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let context = CGContext(
            data: &rgba,
            width: inputSize,
            height: inputSize,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.setFillColor(CGColor(gray: 114.0 / 255.0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: inputSize, height: inputSize))
        context.draw(cgImage, in: CGRect(x: padX, y: padY, width: resizedWidth, height: resizedHeight))

        var chw = [Float](repeating: 0, count: 3 * inputSize * inputSize)
        let plane = inputSize * inputSize
        for y in 0..<inputSize {
            for x in 0..<inputSize {
                let pixelIndex = (y * inputSize + x) * 4
                let outIndex = y * inputSize + x
                chw[outIndex] = Float(rgba[pixelIndex]) / 255.0
                chw[plane + outIndex] = Float(rgba[pixelIndex + 1]) / 255.0
                chw[plane * 2 + outIndex] = Float(rgba[pixelIndex + 2]) / 255.0
            }
        }

        return PreparedInput(
            tensor: chw,
            scale: scale,
            padX: padX,
            padY: padY
        )
    }

    private func decodeOutput(
        _ values: [Float],
        shape: [Int],
        originalSize: CGSize,
        prepared: PreparedInput
    ) -> [TileDetection] {
        guard shape.count == 3 else { return [] }

        let channels = shape[1]
        let count = shape[2]
        guard channels >= 5, values.count >= channels * count else { return [] }

        var detections: [TileDetection] = []
        detections.reserveCapacity(min(count, maxDetections * 3))

        for index in 0..<count {
            let score = values[4 * count + index]
            if score < confidenceThreshold { continue }

            let cx = CGFloat(values[index])
            let cy = CGFloat(values[count + index])
            let w = CGFloat(values[2 * count + index])
            let h = CGFloat(values[3 * count + index])

            var x1 = (cx - w / 2 - prepared.padX) / prepared.scale
            var y1 = (cy - h / 2 - prepared.padY) / prepared.scale
            var x2 = (cx + w / 2 - prepared.padX) / prepared.scale
            var y2 = (cy + h / 2 - prepared.padY) / prepared.scale

            x1 = max(0, min(originalSize.width, x1))
            y1 = max(0, min(originalSize.height, y1))
            x2 = max(0, min(originalSize.width, x2))
            y2 = max(0, min(originalSize.height, y2))

            let pixelWidth = x2 - x1
            let pixelHeight = y2 - y1
            guard pixelWidth > 2, pixelHeight > 2 else { continue }

            let normalized = CGRect(
                x: x1 / originalSize.width,
                y: 1 - (y2 / originalSize.height),
                width: pixelWidth / originalSize.width,
                height: pixelHeight / originalSize.height
            )

            detections.append(
                TileDetection(
                    boundingBox: normalized,
                    confidence: Double(score)
                )
            )
        }

        return detections
    }

    private func nms(_ detections: [TileDetection]) -> [TileDetection] {
        let sorted = detections.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        var kept: [TileDetection] = []
        for detection in sorted {
            if kept.contains(where: { iou($0.boundingBox, detection.boundingBox) > iouThreshold }) {
                continue
            }
            kept.append(detection)
            if kept.count >= maxDetections {
                break
            }
        }

        return kept.sorted { lhs, rhs in
            let yDifference = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
            if yDifference > 0.08 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.midX < rhs.boundingBox.midX
        }
    }

    private func iou(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        if intersection.isNull || intersection.isEmpty { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    private struct PreparedInput {
        var tensor: [Float]
        var scale: CGFloat
        var padX: CGFloat
        var padY: CGFloat
    }

    private final class Runtime {
        static let shared = makeShared()
        static var lastError: String?

        let env: ORTEnv
        let session: ORTSession
        let inputName: String
        let outputName: String

        init?(env: ORTEnv, session: ORTSession, inputName: String, outputName: String) {
            self.env = env
            self.session = session
            self.inputName = inputName
            self.outputName = outputName
        }

        private static func makeShared() -> Runtime? {
            do {
                let env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
                let options = try ORTSessionOptions()
                try options.setIntraOpNumThreads(1)
                try options.setGraphOptimizationLevel(.all)

                if let modelURL = Bundle.main.url(forResource: "MahjongTileDetector", withExtension: "onnx") ??
                    Bundle.main.url(forResource: "MahjongTileDetector", withExtension: "onnx", subdirectory: "PhotoRecognition") {
                    let session = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: options)
                    let inputName = try session.inputNames().first ?? "images"
                    let outputName = try session.outputNames().first ?? "output0"
                    lastError = nil
                    return Runtime(env: env, session: session, inputName: inputName, outputName: outputName)
                }
                lastError = "MahjongTileDetector.onnx not found in app bundle"
            } catch {
                lastError = String(describing: error)
                NSLog("ONNX detector runtime init failed: %@", String(describing: error))
                return nil
            }

            return nil
        }
    }
}
