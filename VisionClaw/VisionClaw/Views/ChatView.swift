//
//  ChatView.swift
//  VisionClaw
//
//  Created by Jessie Hua on 2/27/26.
//

import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var ttsManager = TTSManager()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) {
                        if let last = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                            // Speak assistant responses
                            if last.role == .assistant {
                                ttsManager.speak(last.text)
                            }
                        }
                    }
                }

                Divider()

                // Input bar with voice button
                HStack(spacing: 12) {
                    // Microphone button
                    Button(action: { toggleVoiceInput() }) {
                        Image(systemName: speechManager.isListening ? "mic.fill" : "mic")
                            .font(.title2)
                            .foregroundStyle(speechManager.isListening ? .red : .blue)
                            .frame(width: 44, height: 44)
                            .background(speechManager.isListening ? Color.red.opacity(0.2) : Color.clear)
                            .clipShape(Circle())
                    }
                    
                    // Text field (shows transcription when listening)
                    TextField(
                        speechManager.isListening ? "Listening..." : "Message",
                        text: speechManager.isListening ? $speechManager.transcribedText : $viewModel.inputText,
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .onSubmit { sendMessage() }

                    // Send button
                    Button(action: { sendMessage() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(currentText.isEmpty ? .gray : .blue)
                    }
                    .disabled(currentText.isEmpty)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // TTS toggle
                    Button(action: { ttsManager.ttsEnabled.toggle() }) {
                        Image(systemName: ttsManager.ttsEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                            .foregroundStyle(ttsManager.ttsEnabled ? .blue : .gray)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Connection indicator
                    Circle()
                        .fill(viewModel.isConnected ? .green : .gray)
                        .frame(width: 10, height: 10)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var currentText: String {
        let text = speechManager.isListening ? speechManager.transcribedText : viewModel.inputText
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func toggleVoiceInput() {
        if speechManager.isListening {
            // Stop listening and transfer text
            speechManager.stopListening()
            if !speechManager.transcribedText.isEmpty {
                viewModel.inputText = speechManager.transcribedText
            }
        } else {
            // Stop any TTS and start listening
            ttsManager.stop()
            speechManager.startListening()
        }
    }
    
    private func sendMessage() {
        // If listening, stop and use transcribed text
        if speechManager.isListening {
            speechManager.stopListening()
            viewModel.inputText = speechManager.transcribedText
        }
        
        guard !currentText.isEmpty else { return }
        viewModel.send()
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            Text(message.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.blue : Color(.systemGray5))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if !isUser { Spacer(minLength: 60) }
        }
    }
}
