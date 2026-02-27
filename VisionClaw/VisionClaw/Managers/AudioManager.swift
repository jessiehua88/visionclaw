//
//  AudioManager.swift
//  VisionClaw
//
//  Created by Jessie Hua on 2/27/26.
//

import Foundation
import AVFoundation

/// Manages real-time audio playback of AI responses from the OpenClaw server.
///
/// Takes incoming PCM audio bytes from the WebSocket and plays them
/// through AVAudioEngine, routing output to the connected Bluetooth
/// glasses for a seamless two-way conversation.
final class AudioManager {

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    /// The playback format: 24kHz, mono, PCM Float32.
    /// Adjust this to match whatever format OpenClaw sends back.
    /// Common TTS output rates: 16000, 22050, 24000, 44100.
    private let playbackFormat: AVAudioFormat

    init() {
        // Configure the expected playback format.
        // Change sampleRate if your OpenClaw server uses a different rate.
        playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )!
    }

    // MARK: - Audio Session

    /// Configure AVAudioSession for two-way Bluetooth audio.
    /// Call this before starting the engine.
    ///
    /// - `.playAndRecord`: enables simultaneous input (mic) and output (speaker)
    /// - `.allowBluetooth`: enables HFP profile (required for mic + speaker on BT)
    /// - `.allowBluetoothA2DP`: enables high-quality audio output
    func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try session.setActive(true)
    }

    // MARK: - Engine Lifecycle

    /// Start the audio engine and attach the player node.
    func start() throws {
        try configureSession()

        audioEngine.attach(playerNode)
        audioEngine.connect(
            playerNode,
            to: audioEngine.mainMixerNode,
            format: playbackFormat
        )

        try audioEngine.start()
        playerNode.play()
    }

    /// Stop the audio engine.
    func stop() {
        playerNode.stop()
        audioEngine.stop()
    }

    // MARK: - Playback

    /// Schedule incoming audio bytes for immediate playback.
    ///
    /// The server sends raw PCM audio. We wrap it in an AVAudioPCMBuffer
    /// and schedule it on the player node for gapless streaming playback.
    ///
    /// - Parameter data: Raw PCM audio bytes from the WebSocket.
    ///   Expected format: Float32, 24kHz, mono (matching `playbackFormat`).
    ///   If your server sends Int16 PCM, convert to Float32 first.
    func play(data: Data) {
        // Calculate frame count from byte length.
        // Float32 = 4 bytes per sample.
        let bytesPerSample = 4
        let frameCount = data.count / bytesPerSample

        guard frameCount > 0 else { return }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: playbackFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        // Copy the raw bytes into the buffer's float channel data.
        data.withUnsafeBytes { rawBuffer in
            guard let src = rawBuffer.baseAddress else { return }
            memcpy(buffer.floatChannelData![0], src, data.count)
        }

        // Schedule the buffer for playback.
        // Buffers are queued and played sequentially for gapless audio.
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }
}
