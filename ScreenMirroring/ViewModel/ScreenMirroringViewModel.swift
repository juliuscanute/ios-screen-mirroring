import Foundation
import AVFoundation
import CoreMediaIO
import Combine
import AppKit

class ScreenMirroringViewModel: NSObject, ObservableObject {
    @Published var hasActiveConnection = false
    @Published var devices: [CaptureDevice] = []
    @Published var statusMessage = "Starting discovery..."
    @Published var isDiscovering = false
    @Published var showingDeviceList = false
    
    // Single source of truth for quality:
    @Published var selectedQuality: RecordingQuality = .high {
        didSet {
            recordingVM.selectedQuality = selectedQuality
        }
    }
    
    let screenshotVM = ScreenshotViewModel()
    let recordingVM = ScreenRecordingViewModel()
    
    private var captureSession = AVCaptureSession()
    private var discoveryTimer: Timer?
    private var discoveryAttempts = 0
    private let maxDiscoveryAttempts = 10
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private let videoDataOutputQueue = DispatchQueue(label: "videoDataOutputQueue")
    private var statusCancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        
        // Keep child’s quality in sync with parent
        recordingVM.selectedQuality = selectedQuality
        
        // Subscribe to child status messages
        screenshotVM.$statusMessage
            .filter { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.statusMessage = message
            }
            .store(in: &statusCancellables)
        
        recordingVM.$statusMessage
            .filter { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.statusMessage = message
            }
            .store(in: &statusCancellables)
    }
    
    // MARK: - Public Methods
    
    func startDiscovery() {
        enableScreenCaptureDevices()
        startContinuousDiscovery()
    }
    
    func stopDiscovery() {
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        isDiscovering = false
        statusMessage = "Discovery stopped"
    }
    
    func startCapturing(device: AVCaptureDevice) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.configureCaptureSession(for: device)
            DispatchQueue.main.async {
                self.captureSession.startRunning()
            }
        }
    }
    
    func toggleRecording() {
        if recordingVM.isRecording {
            // stop
            recordingVM.stopRecording()
        } else {
            if let connection = videoDataOutput?.connection(with: .video),
               let inputPort = connection.inputPorts.first,
               let formatDescription = inputPort.formatDescription
            {
                let videoDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                let width = Int(videoDimensions.width)
                let height = Int(videoDimensions.height)
                recordingVM.startRecording(width: width, height: height)
            }
        }
    }
    
    func cleanup() {
        stopDiscovery()
        captureSession.stopRunning()
        captureSession = AVCaptureSession()
        
        // stop recording if active
        if recordingVM.isRecording {
            recordingVM.stopRecording()
        }
        
        // cancel subscriptions
        statusCancellables.forEach { $0.cancel() }
        statusCancellables.removeAll()
        devices = []
        print("All resources released")
    }
    
    func takeScreenshot() {
        screenshotVM.takeScreenshot()
    }
    
    // MARK: - Private Methods
    
    private func startContinuousDiscovery() {
        stopDiscovery()
        discoveryAttempts = 0
        isDiscovering = true
        
        discoverAndConnectToScreenCapture()
        
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.discoverAndConnectToScreenCapture()
        }
    }
    
    private func discoverAndConnectToScreenCapture() {
        discoveryAttempts += 1
        statusMessage = "Discovery attempt \(discoveryAttempts)..."
        
        discoverAvailableDevices()
        
        if let screenCaptureDevice = findScreenCaptureDevice()?.device {
            stopDiscovery()
            showingDeviceList = false
            statusMessage = "Found screen capture device: \(screenCaptureDevice.localizedName)"
            startCapturing(device: screenCaptureDevice)
        } else if discoveryAttempts >= maxDiscoveryAttempts {
            stopDiscovery()
            if !devices.isEmpty {
                showingDeviceList = true
                statusMessage =
                "No dedicated screen capture device found. Please select from list."
            } else {
                statusMessage =
                "No devices found after \(discoveryAttempts) attempts."
            }
        }
    }
    
    private func findScreenCaptureDevice() -> CaptureDevice? {
        devices.first(where: { $0.isScreenMirroringDevice })
    }
    
    private func discoverAvailableDevices() {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .continuityCamera,
            .external,
            .builtInWideAngleCamera
        ]
        let mediaTypes: [AVMediaType] = [.muxed, .video]
        var discoveredDevices: [AVCaptureDevice] = []
        
        for mediaType in mediaTypes {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: mediaType,
                position: .unspecified
            )
            for device in discoverySession.devices {
                if !discoveredDevices.contains(where: { $0.uniqueID == device.uniqueID }) {
                    discoveredDevices.append(device)
                }
            }
        }
        devices = discoveredDevices.map {
            CaptureDevice(name: $0.localizedName, device: $0)
        }
        print("Available devices: \(devices.map { $0.name })")
    }
    
    func getCaptureSession() -> AVCaptureSession {
        captureSession
    }
    
    private func configureCaptureSession(for device: AVCaptureDevice) {
        captureSession.beginConfiguration()
        
        // remove existing inputs and outputs
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }
        
        // create and add input
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                output.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
                output.alwaysDiscardsLateVideoFrames = true
                
                if captureSession.canAddOutput(output) {
                    captureSession.addOutput(output)
                    videoDataOutput = output
                    DispatchQueue.main.async {
                        self.hasActiveConnection = true
                        self.statusMessage = "Connected to \(device.localizedName)"
                    }
                }
            }
        } catch {
            print("Error setting up capture session: \(error)")
        }
        
        captureSession.commitConfiguration()
    }
}

// MARK: - Screen Capture Helper
extension ScreenMirroringViewModel {
    func enableScreenCaptureDevices() {
        var property = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let sizeOfAllow = MemoryLayout<UInt32>.size
        let result = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &property,
            0,
            nil,
            UInt32(sizeOfAllow),
            &allow
        )
        if result != noErr {
            print("Error enabling screen capture devices: \(result)")
        } else {
            print("Screen capture devices enabled.")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension ScreenMirroringViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            screenshotVM.updatePixelBuffer(pixelBuffer)
            
            if recordingVM.isRecording {
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                recordingVM.updatePixelBuffer(pixelBuffer, timestamp: timestamp)
            }
        }
    }
}
