//
//  CaptureDevice.swift
//  ScreenMirroring
//
//  Created by Julius Canute on 26/3/2025.
//


import AVFoundation

struct CaptureDevice {
    let name: String
    let device: AVCaptureDevice
    
    var isScreenMirroringDevice: Bool {
        if let creatorID = device.value(forKey: "_creatorID") as? String,
           creatorID.contains("iOSScreenCapture") {
            return true
        }
        return false
    }
}
