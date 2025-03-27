import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ScreenMirroringViewModel()
    
    var body: some View {
        VStack {
            if !viewModel.showingDeviceList || viewModel.devices.isEmpty {
                CapturePreviewView(viewModel: viewModel)
            } else {
                DeviceListView(viewModel: viewModel)
            }
        }
        .aspectRatio(9.0/16.0, contentMode: .fit)
        .onAppear {
            // Auto-start discovery on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                viewModel.startDiscovery()
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
