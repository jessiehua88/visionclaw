//
//  ChatViewModel.swift
//  VisionClaw
//
//  Created by Jessie Hua on 2/27/26.
//

import Combine
import Foundation
import SwiftUI

/// A single message in the chat conversation.
struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    let timestamp = Date()

    enum Role {
        case user
        case assistant
    }
}

/// Manages the text chat session with the OpenClaw server.
/// Uses its own WebSocket connection independent of the streaming session.
final class ChatViewModel: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isConnected = false

    @AppStorage("serverHost") private var serverHost: String = "10.9.50.189"
    @AppStorage("serverPort") private var serverPort: Int = 18789
    @AppStorage("serverPassword") private var serverPassword: String = ""

    private let webSocket = WebSocketManager()
    private let deviceManager = DeviceIdentityManager()
    private var cancellables = Set<AnyCancellable>()
    private var pendingText: String?
    private var requestId = 0
    private let sessionKey = "agent:main:webchat:dm:visionclaw"

    // Auth state machine
    private enum AuthState {
        case disconnected
        case waitingForChallenge  // WebSocket connected, waiting for server challenge
        case connectSent          // signed connect request sent, waiting for response
        case authenticated        // fully authenticated
    }
    private var authState: AuthState = .disconnected

    init() {
        webSocket.onTextReceived = { [weak self] text in
            guard let self = self else { return }
            self.handleServerMessage(text)
        }

        webSocket.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                self.isConnected = (state == .connected && self.authState == .authenticated)

                if state == .connected && self.authState == .disconnected {
                    self.authState = .waitingForChallenge
                    print("[Chat] Connected, waiting for challenge from server...")
                }

                if state == .disconnected {
                    self.authState = .disconnected
                    self.requestId = 0
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Protocol

    private func nextRequestId() -> String {
        requestId += 1
        return "\(requestId)"
    }

    /// Send the connect request WITH the signed challenge included.
    /// Uses server-provided timestamp and v2 signing format.
    private func sendConnectRequest(nonce: String, timestamp: Int64) {
        let signature = deviceManager.signChallenge(nonce: nonce, timestamp: timestamp)

        let request: [String: Any] = [
            "type": "req",
            "id": nextRequestId(),
            "method": "connect",
            "params": [
                "minProtocol": 3,
                "maxProtocol": 3,
                "client": [
                    "id": "cli",
                    "version": "1.0.0",
                    "platform": "visionos",
                    "mode": "cli"
                ],
                "device": [
                    "id": deviceManager.deviceId,
                    "publicKey": deviceManager.publicKeyBase64,
                    "signature": signature,
                    "signedAt": timestamp,
                    "nonce": nonce
                ],
                "role": "operator",
                "scopes": [] as [String],
                "caps": [] as [String],
                "auth": [
                    "password": serverPassword
                ]
            ] as [String: Any]
        ]
        authState = .connectSent
        sendJSON(request)
        print("[Chat] Sent signed connect request")
    }

    private func sendChatMessage(_ text: String) {
        let request: [String: Any] = [
            "type": "req",
            "id": nextRequestId(),
            "method": "chat.send",
            "params": [
                "sessionKey": sessionKey,
                "message": text,
                "idempotencyKey": UUID().uuidString
            ]
        ]
        sendJSON(request)
    }

    private func sendJSON(_ dict: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let jsonString = String(data: data, encoding: .utf8) {
            print("[Chat] Sending: \(jsonString.prefix(500))")
            webSocket.sendText(jsonString)
        } else {
            print("[Chat] ERROR: Failed to serialize JSON")
        }
    }

    private func handleServerMessage(_ text: String) {
        print("[Chat] Received: \(text.prefix(300))")

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            DispatchQueue.main.async {
                self.messages.append(ChatMessage(role: .assistant, text: text))
            }
            return
        }

        switch type {
        case "event":
            let event = json["event"] as? String ?? ""
            let payload = json["payload"] as? [String: Any] ?? [:]

            if event == "connect.challenge" {
                if let nonce = payload["nonce"] as? String {
                    // JSONSerialization stores numbers as NSNumber;
                    // cast via NSNumber to handle Int, Double, etc.
                    let ts: Int64
                    if let n = payload["ts"] as? NSNumber {
                        ts = n.int64Value
                    } else {
                        ts = Int64(Date().timeIntervalSince1970 * 1000)
                    }
                    print("[Chat] Got challenge nonce: \(nonce), ts: \(ts)")
                    self.sendConnectRequest(nonce: nonce, timestamp: ts)
                }
            } else if event == "chat" {
                // Chat response from the AI — could be full content or streaming delta
                if let content = payload["content"] as? String {
                    DispatchQueue.main.async {
                        self.messages.append(ChatMessage(role: .assistant, text: content))
                    }
                } else if let delta = payload["delta"] as? String {
                    DispatchQueue.main.async {
                        self.appendDelta(delta)
                    }
                }
            } else {
                // Other events
                if let content = payload["text"] as? String ?? payload["message"] as? String ?? payload["content"] as? String {
                    DispatchQueue.main.async {
                        self.messages.append(ChatMessage(role: .assistant, text: content))
                    }
                } else {
                    print("[Chat] Event: \(event)")
                }
            }

        case "res":
            print("[Chat] Got response, authState=\(authState), json keys: \(json.keys.sorted())")
            let ok = json["ok"] as? Bool
            let hasError = json["error"] as? [String: Any]

            if hasError != nil {
                let msg = hasError?["message"] as? String ?? "Unknown error"
                print("[Chat] Error response: \(msg)")
                DispatchQueue.main.async {
                    self.messages.append(ChatMessage(role: .assistant, text: "Error: \(msg)"))
                }
            } else if authState == .connectSent {
                // Any non-error response to connect = authenticated
                DispatchQueue.main.async {
                    self.authState = .authenticated
                    self.isConnected = true
                    print("[Chat] Authenticated successfully")

                    if let text = self.pendingText {
                        self.pendingText = nil
                        self.sendChatMessage(text)
                    }
                }
            } else {
                print("[Chat] Response (ok=\(String(describing: ok))): \(String(describing: json["payload"]))")
            }

        default:
            let fallbackData = json["payload"] as? [String: Any] ?? json["params"] as? [String: Any]
            if let fallbackData = fallbackData,
               let text = fallbackData["text"] as? String ?? fallbackData["message"] as? String ?? fallbackData["content"] as? String {
                DispatchQueue.main.async {
                    self.messages.append(ChatMessage(role: .assistant, text: text))
                }
            }
        }
    }

    /// Append a streaming delta to the last assistant message, or create a new one.
    private func appendDelta(_ delta: String) {
        if let last = messages.last, last.role == .assistant {
            // Replace the last message with appended text
            let updated = ChatMessage(role: .assistant, text: last.text + delta)
            messages[messages.count - 1] = updated
        } else {
            messages.append(ChatMessage(role: .assistant, text: delta))
        }
    }

    // MARK: - Public

    func connect() {
        guard webSocket.state == .disconnected else { return }
        authState = .disconnected
        requestId = 0
        webSocket.connect(host: serverHost, port: serverPort, path: "/")
    }

    func disconnect() {
        webSocket.disconnect()
        pendingText = nil
        authState = .disconnected
        requestId = 0
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        messages.append(ChatMessage(role: .user, text: text))
        inputText = ""

        if authState == .authenticated {
            sendChatMessage(text)
        } else {
            pendingText = text
            connect()
        }
    }
}

