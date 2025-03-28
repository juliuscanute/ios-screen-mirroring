//
//  WebDriverAgentService.swift
//  ScreenMirroring
//
//  Created by Julius Canute on 28/3/2025.
//


import Foundation
import Combine

class WebDriverAgentService: ObservableObject {
    enum WDAStatus: Equatable {
        case notStarted
        case checkingDevice
        case installingWDA
        case launching
        case ready
        case failed(String)
    }
    
    @Published var status: WDAStatus = .notStarted
    @Published var deviceId: String?
    @Published var progress: String = ""
    
    private var wdaProcess: Process?
    private var deviceCheckProcess: Process?
    private let wdaPort = 8100
    private var cancellables = Set<AnyCancellable>()
    private var statusCheckTimer: Timer?
    
    // Bundle path to embedded WDA project
    private var wdaProjectPath: String {

        return Bundle.main.path(forResource: "WebDriverAgent", ofType: "xcodeproj")!
    }
    
    func setupWDA() {
        status = .checkingDevice
        progress = "Checking for connected iOS device..."
        
        Task {
            do {
                // Find connected device
                let deviceId = try await findConnectedDevice()
                self.deviceId = deviceId
                
                // Install and launch WDA
                await MainActor.run {
                    self.status = .installingWDA
                    self.progress = "Installing WebDriverAgent on device..."
                }
                
                try await installAndLaunchWDA(deviceId: deviceId)
                
                // Start checking if WDA is responding
                await MainActor.run {
                    self.status = .launching
                    self.progress = "Launching WebDriverAgent..."
                    self.startCheckingWDAStatus()
                }
            } catch {
                await MainActor.run {
                    self.status = .failed(error.localizedDescription)
                    self.progress = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func startCheckingWDAStatus() {
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task {
                if await self.isWDAResponding() {
                    await MainActor.run {
                        self.status = .ready
                        self.progress = "WebDriverAgent is running"
                        self.statusCheckTimer?.invalidate()
                    }
                }
            }
        }
    }
    
    private func findConnectedDevice() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["xctrace", "list", "devices"]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            
            do {
                try process.run()
                deviceCheckProcess = process
                
                process.terminationHandler = { process in
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    
                    // Parse for real device (not simulator)
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines {
                        if line.contains("iPhone") && !line.contains("Simulator") {
                            // Extract device ID
                            if let range = line.range(of: "(\\d+\\.\\d+(\\.\\d+)?)\\s+\\((\\w+-\\w+-\\w+-\\w+-\\w+)\\)", options: .regularExpression) {
                                let match = line[range]
                                if let idRange = match.range(of: "[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}", options: .regularExpression) {
                                    let deviceId = String(match[idRange])
                                    continuation.resume(returning: deviceId)
                                    return
                                }
                            }
                        }
                    }
                    continuation.resume(throwing: NSError(domain: "WebDriverAgent", code: 1, userInfo: [NSLocalizedDescriptionKey: "No iOS device found. Please connect an iPhone or iPad."]))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func installAndLaunchWDA(deviceId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
            process.arguments = [
                "-project", wdaProjectPath,
                "-scheme", "WebDriverAgentRunner",
                "-destination", "id=\(deviceId)",
                "test"
            ]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            let errorPipe = Pipe()
            process.standardError = errorPipe
            
            // Update progress based on xcodebuild output
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self = self else { return }
                let data = handle.availableData
                if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                    if output.contains("Test session") {
                        Task { @MainActor in
                            self.progress = "WebDriverAgent launched successfully"
                            continuation.resume()
                        }
                    } else if output.contains("Building") {
                        Task { @MainActor in
                            self.progress = "Building WebDriverAgent..."
                        }
                    } else if output.contains("Testing") {
                        Task { @MainActor in
                            self.progress = "Starting WebDriverAgent..."
                        }
                    }
                }
            }
            
            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                    if output.contains("error:") {
                        Task { @MainActor in
                            self?.progress = "Error: \(output)"
                            continuation.resume(throwing: NSError(domain: "WebDriverAgent", code: 2, userInfo: [NSLocalizedDescriptionKey: output]))
                        }
                    }
                }
            }
            
            do {
                try process.run()
                self.wdaProcess = process
                
                // If no success callback after 60 seconds, timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                    if process.isRunning, self?.status != .ready {
                        continuation.resume(throwing: NSError(domain: "WebDriverAgent", code: 3, userInfo: [NSLocalizedDescriptionKey: "WDA installation timed out"]))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func isWDAResponding() async -> Bool {
        guard let deviceId = deviceId else { return false }
        
        // WDA usually runs on port 8100 for the first device
        let urlString = "http://localhost:\(wdaPort)/status"
        guard let url = URL(string: urlString) else { return false }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return true
            }
        } catch {
            print("WDA not responding yet: \(error)")
        }
        return false
    }
    
    func sendTap(at point: CGPoint) {
        let urlString = "http://localhost:\(wdaPort)/wda/tap/0"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let payload = ["x": point.x, "y": point.y]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func sendSwipe(from startPoint: CGPoint, to endPoint: CGPoint, duration: Double = 0.3) {
        let urlString = "http://localhost:\(wdaPort)/wda/dragfromtoforduration"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let payload: [String: Any] = [
            "fromX": startPoint.x,
            "fromY": startPoint.y,
            "toX": endPoint.x,
            "toY": endPoint.y,
            "duration": duration
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request).resume()
    }
    
    deinit {
        wdaProcess?.terminate()
        deviceCheckProcess?.terminate()
        statusCheckTimer?.invalidate()
    }
}
