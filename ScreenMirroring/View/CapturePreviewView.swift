import SwiftUI
import AVFoundation

struct CapturePreviewView: View {
    @ObservedObject var viewModel: ScreenMirroringViewModel

    var body: some View {
        VStack {
            // Preview area
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
            
            // Status
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.horizontal)
                .padding(.top, 8)
            
            // Controls
            VStack(spacing: 16) {
                if viewModel.isDiscovering {
                    Button("Cancel Discovery") {
                        viewModel.stopDiscovery()
                    }
                }
                
                // Screenshot and recording controls
                if viewModel.hasActiveConnection {
                    // Show quality picker only if not recording yet
                    if !viewModel.recordingVM.isRecording {
                        HStack {
                            Picker("Quality", selection: $viewModel.selectedQuality) {
                                ForEach(RecordingQuality.allCases) { quality in
                                    Text(quality.rawValue).tag(quality)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(maxWidth: 160)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Buttons
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
                            .frame(maxWidth: (geometry.size.width - 20) / 2)
                            .background(Color.blue)
                            .cornerRadius(8)
                            
                            // Record / Stop
                            Button(action: {
                                viewModel.toggleRecording()
                            }) {
                                Label(
                                    viewModel.recordingVM.isRecording
                                        ? "Stop Recording"
                                        : "Record",
                                    systemImage: viewModel.recordingVM.isRecording
                                        ? "stop.circle"
                                        : "record.circle"
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .foregroundColor(.white)
                            }
                            .frame(maxWidth: (geometry.size.width - 20) / 2)
                            .background(viewModel.recordingVM.isRecording ? Color.red : Color.green)
                            .cornerRadius(8)
                        }
                    }
                    .frame(height: 36)
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
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// Example preview
struct CapturePreviewView_Previews: PreviewProvider {
    static var previews: some View {
        CapturePreviewView(viewModel: ScreenMirroringViewModel())
            .frame(width: 400, height: 600)
    }
}
