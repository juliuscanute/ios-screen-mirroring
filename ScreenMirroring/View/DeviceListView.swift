//
//  DeviceListView.swift
//  ScreenMirroring
//
//  Created by Julius Canute on 26/3/2025.
//


import SwiftUI
import AVFoundation

struct DeviceListView: View {
    @ObservedObject var viewModel: ScreenMirroringViewModel
    
    var body: some View {
        VStack {
            Text("Select a Device")
                .font(.headline)
                .padding(.top)
            
            List(viewModel.devices, id: \.name) { captureDevice in
                HStack {
                    Button(captureDevice.name) {
                        viewModel.showingDeviceList = false
                        viewModel.startCapturing(device: captureDevice.device)
                    }
                    
                    if captureDevice.isScreenMirroringDevice {
                        Spacer()
                        Image(systemName: "display.and.arrow.down")
                            .foregroundColor(.green)
                    }
                }
            }
            .frame(height: 200)
            
            Button("Cancel") {
                viewModel.showingDeviceList = false
            }
            .padding(.bottom)
        }
    }
}