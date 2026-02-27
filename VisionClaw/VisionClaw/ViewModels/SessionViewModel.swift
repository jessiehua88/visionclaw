//
//  SessionViewModel.swift
//  VisionClaw
//
//  Created by Jessie Hua on 2/27/26.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

/// Wires together the hardware (DAT SDK), network (WebSocket),
/// and audio playback managers into a single observable state machine.
final class SessionViewModel: ObservableObject {

    @Published var isStreaming = false
    @Published var connectionState: ConnectionState = .disconnected
    @Published var glassesConnected = false

    // User-configurable server settings (persisted across launches)
    @AppStorage("serverHost") var serverHost: String = "10.9.50.189"
    @AppStorage("serverPort") var serverPort: Int = 18789
    @AppStorage("serverPassword") var serverPassword: String = ""

    private let datManager = DATSDKManager()
    private let webSocket = WebSocketManager()
    private let audio = AudioManager()

    // Phone microphone capture
    private var micEngine: AVAudioEngine?

    init() {
        // Initialize the DAT SDK once at startup.
        datManager.configure()

        // Wire up data flow callbacks.
        setupPipeline()
    }

    // MARK: - Data Pipeline

    /// Connect the managers into a streaming pipeline:
    ///   Phone mic -> WebSocket -> Server
    ///   Glasses camera -> WebSocket -> Server
    ///   Server -> WebSocket -> Audio playback -> Glasses speaker
    private func setupPipeline() {
        // Glasses camera frame -> send to server
        datManager.onFrameCaptured = { [weak self] jpegData in
            self?.webSocket.sendVideoFrame(jpegData)
        }

        // Server AI audio response -> play through glasses speaker
        webSocket.onAudioReceived = { [weak self] audioData in
            self?.audio.play(data: audioData)
        }
    }

    // MARK: - Phone Microphone Capture

    /// Start capturing audio from the phone's microphone and
    /// streaming it to the server via WebSocket.
    /// The DAT SDK doesn't expose the glasses mic, so we use
    /// the phone mic (or Bluetooth HFP mic if glasses are
    /// connected as a Bluetooth audio device).
    private func startMicCapture() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            // Convert to PCM data and send
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            let data = Data(bytes: channelData, count: frameCount * MemoryLayout<Float>.size)
            self.webSocket.sendAudio(data)
        }

        engine.prepare()
        try engine.start()
        micEngine = engine
    }

    private func stopMicCapture() {
        micEngine?.inputNode.removeTap(onBus: 0)
        micEngine?.stop()
        micEngine = nil
    }

    // MARK: - Session Control

    /// Start a streaming session: connect glasses, server, and audio.
    func startSession() {
        guard !isStreaming else { return }

        connectionState = .connecting

        // 1. Connect to the OpenClaw server
        webSocket.connect(host: serverHost, port: serverPort)

        // 2. Start audio playback engine
        do {
            try audio.start()
        } catch {
            print("[Session] Audio engine failed to start: \(error)")
            webSocket.disconnect()
            connectionState = .disconnected
            return
        }

        // 3. Start phone mic capture
        do {
            try startMicCapture()
        } catch {
            print("[Session] Mic capture failed to start: \(error)")
        }

        // 4. Start glasses registration / stream
        datManager.startRegistration()

        isStreaming = true
        connectionState = .connected

        // Observe glasses connection state
        observeGlassesState()
    }

    /// Stop the streaming session and tear down all connections.
    func stopSession() {
        datManager.disconnect()
        webSocket.disconnect()
        audio.stop()
        stopMicCapture()

        isStreaming = false
        connectionState = .disconnected
        glassesConnected = false
    }

    /// Toggle the session on/off.
    func toggleSession() {
        if isStreaming {
            stopSession()
        } else {
            startSession()
        }
    }

    // MARK: - Observation

    private func observeGlassesState() {
        // Poll the DAT manager's connection state.
        // Replace with Combine publisher if the SDK supports it.
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            if !self.isStreaming {
                timer.invalidate()
                return
            }
            DispatchQueue.main.async {
                self.glassesConnected = self.datManager.isConnected
            }
        }
    }
}
