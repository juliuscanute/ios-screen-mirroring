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

        outputWidth = width
        outputHeight = height

        setupAssetWriter()
        assetWriter?.startWriting()
        assetWriter?.startSession(atSourceTime: .zero)
        guard assetWriter != nil else {
            print("Asset Writer setup failed.")
            return
        }

        guard assetWriter != nil else {
            statusMessage = "Asset Writer setup failed."
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
            self.recordingDuration += 1.0 // Increment the duration
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
                    self?.statusMessage = "Recording saved"
                    self?.promptForSaveLocation()
                    print("Recording finished")
                    self?.resetRecording()
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

        savePanel.begin { result in
            if result == .OK, let targetURL = savePanel.url {
                try? FileManager.default.copyItem(at: tempURL, to: targetURL)
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
    }
}
