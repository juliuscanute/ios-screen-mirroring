import Foundation
import AVFoundation
import CoreVideo
import Combine
import AppKit
import UniformTypeIdentifiers

class ScreenRecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var statusMessage = ""
    
    // Keep this if you reference it in startRecording or elsewhere
    @Published var selectedQuality: RecordingQuality = .high

    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var timer: Timer?
    private var tempURL: URL?
    private var firstFrameTime: CMTime?
    private var frameCount = 0
    private var outputWidth = 0
    private var outputHeight = 0

    // Start recording to MP4 file
    func startRecording(width: Int, height: Int) {
        guard !isRecording else { return }

        // Detect orientation
        let isPortrait = height > width
        
        // Calculate dimensions that maintain aspect ratio
        // (If you are using 'selectedQuality' here, you can adjust logic as desired)
        let targetWidth = isPortrait ? 720 : 1280
        let dimensions = calculateOutputDimensions(
            sourceWidth: width,
            sourceHeight: height,
            targetWidth: targetWidth
        )

        outputWidth = dimensions.width
        outputHeight = dimensions.height

        setupAssetWriter()
        assetWriter?.startWriting()
        assetWriter?.startSession(atSourceTime: .zero)

        guard assetWriter != nil else {
            statusMessage = "Asset Writer setup failed."
            print(statusMessage)
            return
        }

        isRecording = true
        recordingDuration = 0
        frameCount = 0
        statusMessage = "Recording started"
        print("Recording started")

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, self.isRecording else {
                timer.invalidate()
                return
            }
            self.recordingDuration += 1.0
            DispatchQueue.main.async {
                self.statusMessage = "Recording: \(self.formattedDuration) - Frames: \(self.frameCount)"
            }
        }
    }

    // Stop recording and finalize MP4 file
    func stopRecording() {
        guard isRecording, let writer = assetWriter else {
            resetRecording()
            return
        }

        isRecording = false

        if writer.status == .writing {
            assetWriterInput?.markAsFinished()

            writer.finishWriting { [weak self] in
                DispatchQueue.main.async {
                    self?.statusMessage = "Processing recording..."
                    self?.promptForSaveLocation()
                    print("Recording finished")
                    // resetRecording() is called after user saves or cancels
                }
            }
        } else {
            statusMessage = "Recording was not started properly."
            print("Cannot finalize, writer status: \(assetWriter?.status.rawValue ?? -1)")
            resetRecording()
        }
    }

    func updatePixelBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        if firstFrameTime == nil {
            firstFrameTime = timestamp
            assetWriter?.startSession(atSourceTime: .zero)
        }
        guard let startTime = firstFrameTime else { return }

        let relativeTime = CMTimeSubtract(timestamp, startTime)
        guard isRecording,
              let adaptor = pixelBufferAdaptor,
              adaptor.assetWriterInput.isReadyForMoreMediaData else {
            return
        }

        if adaptor.append(pixelBuffer, withPresentationTime: relativeTime) {
            frameCount += 1
        }
    }

    private func setupAssetWriter() {
        let tempDir = FileManager.default.temporaryDirectory
        tempURL = tempDir.appendingPathComponent("recording_\(UUID().uuidString).mp4")

        do {
            assetWriter = try AVAssetWriter(outputURL: tempURL!, fileType: .mp4)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: outputWidth,
                AVVideoHeightKey: outputHeight
            ]

            assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            assetWriterInput?.expectsMediaDataInRealTime = true

            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: assetWriterInput!,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                    kCVPixelBufferWidthKey as String: outputWidth,
                    kCVPixelBufferHeightKey as String: outputHeight
                ]
            )

            if let input = assetWriterInput, assetWriter!.canAdd(input) {
                assetWriter!.add(input)
            }
        } catch {
            statusMessage = "Setup error: \(error.localizedDescription)"
            print(statusMessage)
        }
    }

    private var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func resetRecording() {
        assetWriter = nil
        assetWriterInput = nil
        pixelBufferAdaptor = nil
        firstFrameTime = nil
        frameCount = 0
        tempURL = nil
        recordingDuration = 0
        outputWidth = 0
        outputHeight = 0
        isRecording = false
    }

    private func promptForSaveLocation() {
        guard let tempURL = tempURL else { return }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = tempURL.lastPathComponent

        if #available(macOS 11.0, *) {
            savePanel.allowedContentTypes = [UTType.mpeg4Movie]
        } else {
            savePanel.allowedFileTypes = ["mp4"]
        }

        savePanel.begin { [weak self] result in
            guard let self = self else { return }
            
            if result == .OK, let targetURL = savePanel.url {
                do {
                    try FileManager.default.copyItem(at: tempURL, to: targetURL)
                    try FileManager.default.removeItem(at: tempURL)
                    self.statusMessage = "Recording saved"
                } catch {
                    self.statusMessage = "Error saving recording: \(error.localizedDescription)"
                }
            } else {
                // User canceled
                self.statusMessage = "Recording not saved"
                try? FileManager.default.removeItem(at: tempURL)
            }
            self.resetRecording()
        }
    }

    private func calculateOutputDimensions(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int? = nil,
        targetHeight: Int? = nil
    ) -> (width: Int, height: Int) {
        guard targetWidth != nil || targetHeight != nil else {
            return (sourceWidth, sourceHeight)
        }

        let aspectRatio = Double(sourceWidth) / Double(sourceHeight)

        if let tw = targetWidth {
            let calcHeight = Int(Double(tw) / aspectRatio)
            return (tw, calcHeight)
        }
        if let th = targetHeight {
            let calcWidth = Int(Double(th) * aspectRatio)
            return (calcWidth, th)
        }
        return (sourceWidth, sourceHeight)
    }
}

// Recording quality enum, also used in the parent
enum RecordingQuality: String, CaseIterable, Identifiable {
    case low = "Low (480p)"
    case medium = "Medium (720p)"
    case high = "High (1080p)"
    case original = "Original Size"
    
    var id: String { rawValue }
    
    var dimensions: (width: Int?, height: Int?) {
        switch self {
        case .low: return (640, 480)
        case .medium: return (1280, 720)
        case .high: return (1920, 1080)
        case .original: return (nil, nil)
        }
    }
}
