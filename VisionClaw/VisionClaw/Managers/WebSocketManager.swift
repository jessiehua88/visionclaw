//
//  WebSocketManager.swift
//  VisionClaw
//
//  Created by Jessie Hua on 2/27/26.
//

import Combine
import Foundation

/// Connection state for the WebSocket.
enum ConnectionState: String {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Active Session"
}

/// Manages a persistent, bi-directional WebSocket connection to the
/// local OpenClaw voice streaming server.
///
/// Upstream (phone -> server):
///   - Audio: raw PCM bytes with a 1-byte prefix (0x01)
///   - Video: JPEG bytes with a 1-byte prefix (0x02)
///
/// Downstream (server -> phone):
///   - Binary audio chunks (AI synthesized voice) for playback
final class WebSocketManager: ObservableObject {

    @Published var state: ConnectionState = .disconnected

    /// Called when audio bytes are received from the server (AI response).
    var onAudioReceived: ((Data) -> Void)?

    /// Called when a text message is received from the server.
    var onTextReceived: ((String) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var serverURL: URL?

    // Binary message type prefixes for multiplexing audio/video
    // on a single WebSocket connection.
    //
    // Protocol:
    //   Byte 0: message type (0x01 = audio, 0x02 = video)
    //   Bytes 1..N: payload
    //
    // The server should parse byte 0 to determine the stream type.
    private static let audioPrefix: UInt8 = 0x01
    private static let videoPrefix: UInt8 = 0x02

    init() {}

    // MARK: - Connection

    /// Connect to the OpenClaw server at a specific path.
    /// - Parameters:
    ///   - host: Server IP address (e.g. "127.0.0.1")
    ///   - port: Server port (e.g. 18789)
    ///   - path: URL path (e.g. "/voice/stream" or "/")
    ///   - password: Optional authentication password (sent as query param)
    func connect(host: String, port: Int, path: String = "/voice/stream", password: String? = nil) {
        guard state == .disconnected else {
            print("[WebSocket] Already \(state.rawValue), skipping connect")
            return
        }

        var urlString = "ws://\(host):\(port)\(path)"
        if let password = password, !password.isEmpty {
            let encoded = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? password
            urlString += "?password=\(encoded)"
        }
        guard let url = URL(string: urlString) else {
            print("[WebSocket] Invalid URL: \(urlString)")
            return
        }

        serverURL = url
        state = .connecting
        print("[WebSocket] Connecting to \(urlString)")

        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        // Start listening IMMEDIATELY so we catch the server's challenge
        // event which arrives right after the connection opens.
        listenForMessages()

        // Mark connected so sendText() works when the challenge handler fires.
        state = .connected
        print("[WebSocket] State set to connected for \(urlString)")
    }

    /// Disconnect from the server.
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        state = .disconnected
    }

    // MARK: - Sending Data

    /// Send a chunk of 16kHz PCM audio to the server.
    /// The audio is prefixed with 0x01 so the server can identify it as audio.
    func sendAudio(_ pcmData: Data) {
        guard state == .connected else { return }

        // Prepend the audio type prefix byte
        var payload = Data([Self.audioPrefix])
        payload.append(pcmData)

        let message = URLSessionWebSocketTask.Message.data(payload)
        webSocketTask?.send(message) { error in
            if let error = error {
                print("[WebSocket] Audio send error: \(error)")
            }
        }
    }

    /// Send a JPEG video frame to the server.
    /// The frame is prefixed with 0x02 so the server can identify it as video.
    func sendVideoFrame(_ jpegData: Data) {
        guard state == .connected else { return }

        // Prepend the video type prefix byte
        var payload = Data([Self.videoPrefix])
        payload.append(jpegData)

        let message = URLSessionWebSocketTask.Message.data(payload)
        webSocketTask?.send(message) { error in
            if let error = error {
                print("[WebSocket] Video send error: \(error)")
            }
        }
    }

    /// Send a text message to the server.
    func sendText(_ text: String) {
        guard state == .connected else {
            print("[WebSocket] Cannot send, state is \(state.rawValue)")
            return
        }

        print("[WebSocket] Sending text: \(text)")
        let message = URLSessionWebSocketTask.Message.string(text)
        webSocketTask?.send(message) { error in
            if let error = error {
                print("[WebSocket] Text send error: \(error)")
            } else {
                print("[WebSocket] Text sent successfully")
            }
        }
    }

    // MARK: - Receiving Data

    /// Continuously listen for incoming messages from the server.
    /// The server sends binary audio chunks (AI voice response).
    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    // Server sends raw audio bytes for playback
                    self.onAudioReceived?(data)
                case .string(let text):
                    self.onTextReceived?(text)
                @unknown default:
                    break
                }

                // Continue listening for the next message
                self.listenForMessages()

            case .failure(let error):
                print("[WebSocket] Receive error: \(error)")
                DispatchQueue.main.async {
                    self.state = .disconnected
                }
            }
        }
    }
}
