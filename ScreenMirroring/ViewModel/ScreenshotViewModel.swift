//
//  ScreenshotViewModel.swift
//  ScreenMirroring
//
//  Created by Julius Canute on 26/3/2025.
//


import Foundation
import AVFoundation
import AppKit
import Combine

class ScreenshotViewModel: ObservableObject {
    @Published var statusMessage = ""
    private var currentPixelBuffer: CVPixelBuffer?
    private var screenshotCounter = 1
    
    // Called by the main ViewModel when new frames are available
    func updatePixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        self.currentPixelBuffer = pixelBuffer
    }
    
    func takeScreenshot() {
        guard let pixelBuffer = currentPixelBuffer else {
            statusMessage = "Cannot take screenshot: No video frame available"
            return
        }
        
        // Convert pixel buffer to CGImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            statusMessage = "Failed to create image from video frame"
            return
        }
        
        // Create NSImage from CGImage
        let size = NSSize(width: CVPixelBufferGetWidth(pixelBuffer),
                          height: CVPixelBufferGetHeight(pixelBuffer))
        let nsImage = NSImage(cgImage: cgImage, size: size)
        
        // Show save dialog
        DispatchQueue.main.async {
            self.showSaveDialog(for: nsImage)
        }
    }
    
    private func showSaveDialog(for image: NSImage) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        
        // Create a nice default filename with date/time
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        savePanel.nameFieldStringValue = "ScreenMirror-\(timestamp).png"
        
        savePanel.message = "Choose a location to save the screenshot"
        savePanel.prompt = "Save Screenshot"
        
        savePanel.beginSheetModal(for: NSApp.mainWindow!) { response in
            if response == .OK, let url = savePanel.url {
                self.saveImage(image, to: url)
            } else {
                self.statusMessage = "Screenshot cancelled"
            }
        }
    }
    
    private func saveImage(_ image: NSImage, to url: URL) {
        // Convert NSImage to PNG data
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            statusMessage = "Failed to convert image to PNG"
            return
        }
        
        // Write to file
        do {
            try pngData.write(to: url)
            statusMessage = "Screenshot saved successfully"
            print("Screenshot saved to: \(url.path)")
        } catch {
            statusMessage = "Failed to save screenshot: \(error.localizedDescription)"
            print("Failed to save screenshot: \(error)")
        }
    }
}
