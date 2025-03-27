import SwiftUI
import AVFoundation

struct CapturePreviewView: View {
    @ObservedObject var viewModel: ScreenMirroringViewModel
    
    var body: some View {
        VStack {
            // Preview with proper aspect ratio
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    CameraPreview(captureSession: viewModel.getCaptureSession())
                        .cornerRadius(8)
                        .shadow(radius: 4)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.horizontal)
                .padding(.top, 8)
            
            // Controls
            VStack(spacing: 16) {
                // Discovery button
                if viewModel.isDiscovering {
                    Button("Cancel Discovery") {
                        viewModel.stopDiscovery()
                    }
                }
                
                // Screenshot and recording buttons grouped together
                if viewModel.hasActiveConnection {
                    GeometryReader { geometry in
                        HStack(spacing: 20) {
                            // Screenshot button
                            Button(action: {
                                viewModel.takeScreenshot()
                            }) {
                                Label("Screenshot", systemImage: "camera")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: (geometry.size.width - 20) / 2) // Equal width minus spacing
                            .background(Color.blue)
                            .cornerRadius(8)
                            
                            // Recording button
                            Button(action: {
                                viewModel.toggleRecording()
                            }) {
                                Label(
                                    viewModel.recordingVM.isRecording ? "Stop Recording" : "Record",
                                    systemImage: viewModel.recordingVM.isRecording ? "stop.circle" : "record.circle"
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .foregroundColor(.white)
                            }
                            .frame(maxWidth: (geometry.size.width - 20) / 2) // Equal width minus spacing
                            .background(viewModel.recordingVM.isRecording ? Color.red : Color.green)
                            .cornerRadius(8)
                        }
                        .frame(maxWidth: geometry.size.width)
                    }
                    .frame(height: 36) // Fixed height for the buttons row
                }
                
                // Recording indicator
                if viewModel.recordingVM.isRecording {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(0.8)
                        
                        Text(formatDuration(viewModel.recordingVM.recordingDuration))
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                }
            }
            .padding(.bottom, 16)
            .padding(.horizontal)
        }
    }
    
    // Format duration as MM:SS
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Preview Mock ViewModel
class PreviewMockViewModel: ScreenMirroringViewModel {
    override init() {
        super.init()
    }
    
    convenience init(discovering: Bool, connected: Bool, statusMessage: String) {
        self.init()
        self.isDiscovering = discovering
        self.hasActiveConnection = connected
        self.statusMessage = statusMessage
    }
    
    override func takeScreenshot() {
        self.statusMessage = "Screenshot taken (preview mode)"
    }
    
    override func stopDiscovery() {
        self.isDiscovering = false
        self.statusMessage = "Discovery stopped (preview mode)"
    }
    
    override func getCaptureSession() -> AVCaptureSession {
        return AVCaptureSession()
    }
}

// MARK: - Preview
struct CapturePreviewView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Preview with active connection (standard aspect ratio)
            CapturePreviewView(viewModel: PreviewMockViewModel(
                discovering: false,
                connected: true, 
                statusMessage: "Connected to iPhone"
            ))
            .frame(width: 500, height: 700)
            .previewDisplayName("Connected")
            
            // Preview with landscape orientation
            CapturePreviewView(viewModel: {
                let vm = PreviewMockViewModel(
                    discovering: false,
                    connected: true,
                    statusMessage: "Landscape orientation"
                )
                return vm
            }())
            .frame(width: 700, height: 400)
            .previewDisplayName("Landscape")
        }
    }
}
