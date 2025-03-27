import SwiftUI
import AVFoundation
import Cocoa

struct CameraPreview: NSViewRepresentable {
    let captureSession: AVCaptureSession
        
    func makeNSView(context: Context) -> NSView {
        let nsView = NSView(frame: .zero)
        nsView.wantsLayer = true

        // Create the preview layer with the capture session
        captureSession.sessionPreset = .hd1920x1080
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspect // Keep aspect ratio
        previewLayer.frame = nsView.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        
        nsView.layer?.addSublayer(previewLayer)
        return nsView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Make sure the preview layer fills the view
        if let previewLayer = nsView.layer?.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = nsView.bounds
        }
    }
}
