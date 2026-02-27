//
//  DATSDKManager.swift
//  VisionClaw
//
//  Created by Jessie Hua on 2/27/26.
//

import Combine
import CoreMedia
import Foundation
import MWDATCamera
import MWDATCore
import UIKit

/// Manages the Meta DAT SDK connection to Ray-Ban smart glasses.
/// Handles camera frames from the glasses via MWDATCamera's StreamSession.
///
/// Note: The DAT SDK provides camera streaming but does not expose
/// the glasses microphone audio. For audio input, use the phone's
/// own microphone via AVAudioEngine/AVAudioSession.
final class DATSDKManager: ObservableObject {

    @Published var isConnected = false

    /// Called when a new JPEG frame is captured from the glasses camera.
    /// Frames are throttled to ~1fps and compressed to JPEG.
    var onFrameCaptured: ((Data) -> Void)?

    private var streamSession: StreamSession?
    private var videoListenerToken: (any AnyListenerToken)?
    private var stateListenerToken: (any AnyListenerToken)?
    private var lastFrameTime: Date = .distantPast
    private let frameCaptureInterval: TimeInterval = 1.0 // ~1fps

    init() {}

    // MARK: - SDK Lifecycle

    /// Call once at app launch to initialize the DAT SDK.
    /// You must have configured your App ID and Info.plist keys
    /// per Meta's setup guide before calling this.
    func configure() {
        do {
            try Wearables.configure()
        } catch {
            print("[DATSDKManager] Configure failed: \(error)")
        }
    }

    /// Begin scanning/registering for glasses.
    /// The Meta AI app must have paired the glasses first —
    /// this triggers the Bluetooth handoff to your app.
    func startRegistration() {
        Task { @MainActor in
            do {
                try await Wearables.shared.startRegistration()
                // After registration, set up the camera stream session.
                // Use AutoDeviceSelector to automatically pick the connected device.
                let deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
                let session = StreamSession(deviceSelector: deviceSelector)
                self.streamSession = session
                self.setupStreams(session: session)
                await session.start()
                self.isConnected = true
            } catch {
                print("[DATSDKManager] Registration failed: \(error)")
                self.isConnected = false
            }
        }
    }

    /// Stop all streams and disconnect.
    func disconnect() {
        Task { @MainActor in
            await videoListenerToken?.cancel()
            videoListenerToken = nil
            await stateListenerToken?.cancel()
            stateListenerToken = nil
            await streamSession?.stop()
            streamSession = nil
            self.isConnected = false
        }
    }

    // MARK: - Stream Setup

    private func setupStreams(session: StreamSession) {
        // Listen for video frames from the glasses camera.
        // The SDK delivers VideoFrame objects via the Announcer pattern.
        videoListenerToken = session.videoFramePublisher.listen { [weak self] videoFrame in
            guard let self = self else { return }

            // Throttle: skip frames until 1 second has elapsed.
            let now = Date()
            guard now.timeIntervalSince(self.lastFrameTime) >= self.frameCaptureInterval else {
                return
            }
            self.lastFrameTime = now

            // Convert VideoFrame -> JPEG Data
            if let jpegData = self.jpegData(from: videoFrame) {
                self.onFrameCaptured?(jpegData)
            }
        }

        // Optionally observe session state changes.
        stateListenerToken = session.statePublisher.listen { [weak self] state in
            DispatchQueue.main.async {
                self?.isConnected = (state == .streaming)
            }
        }
    }

    // MARK: - Data Conversion

    /// Convert a VideoFrame to compressed JPEG data.
    private func jpegData(from videoFrame: VideoFrame, quality: CGFloat = 0.5) -> Data? {
        // The SDK's VideoFrame provides a convenience method to create a UIImage.
        guard let uiImage = videoFrame.makeUIImage() else {
            return nil
        }
        return uiImage.jpegData(compressionQuality: quality)
    }
}
