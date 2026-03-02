//
//  TTSManager.swift
//  VisionClaw
//
//  Text-to-speech using AVSpeechSynthesizer
//

import AVFoundation
import SwiftUI

/// Manages text-to-speech (text → voice)
final class TTSManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    
    @Published var isSpeaking = false
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = true
    @AppStorage("ttsVoiceId") var voiceIdentifier: String = ""
    @AppStorage("ttsRate") var speechRate: Double = 0.5  // 0.0 - 1.0
    
    private let synthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        synthesizer.delegate = self
        
        // Configure audio session for playback
        configureAudioSession()
    }
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            print("[TTS] Audio session error: \(error)")
        }
    }
    
    // MARK: - Speaking
    
    /// Speak the given text
    func speak(_ text: String) {
        guard ttsEnabled else { return }
        guard !text.isEmpty else { return }
        
        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        // Configure audio session
        configureAudioSession()
        try? AVAudioSession.sharedInstance().setActive(true)
        
        let utterance = AVSpeechUtterance(string: text)
        
        // Set voice (use selected or default)
        if !voiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            // Default to a nice English voice
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        
        // Set rate (0.0 - 1.0, default 0.5)
        utterance.rate = Float(speechRate) * AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        synthesizer.speak(utterance)
        
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
        print("[TTS] Speaking: \(text.prefix(50))...")
    }
    
    /// Stop speaking
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
    
    // MARK: - Available Voices
    
    /// Get list of available English voices
    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.starts(with: "en")
        }.sorted { $0.name < $1.name }
    }
}
