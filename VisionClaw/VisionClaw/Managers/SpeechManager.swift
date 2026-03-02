//
//  SpeechManager.swift
//  VisionClaw
//
//  Speech-to-text using Apple's Speech framework
//

import AVFoundation
import Speech
import SwiftUI

/// Manages speech recognition (voice → text)
final class SpeechManager: ObservableObject {
    
    @Published var isListening = false
    @Published var transcribedText = ""
    @Published var isAuthorized = false
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        requestAuthorization()
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isAuthorized = (status == .authorized)
                if status != .authorized {
                    print("[Speech] Not authorized: \(status)")
                }
            }
        }
    }
    
    // MARK: - Recording
    
    /// Start listening and transcribing speech
    func startListening() {
        guard isAuthorized else {
            print("[Speech] Not authorized")
            return
        }
        
        guard !isListening else { return }
        
        // Reset any existing task
        stopListening()
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[Speech] Audio session error: \(error)")
            return
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                DispatchQueue.main.async {
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }
            
            if error != nil || (result?.isFinal ?? false) {
                self.stopListening()
            }
        }
        
        // Configure audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isListening = true
                self.transcribedText = ""
            }
            print("[Speech] Started listening")
        } catch {
            print("[Speech] Engine start error: \(error)")
        }
    }
    
    /// Stop listening and finalize transcription
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        DispatchQueue.main.async {
            self.isListening = false
        }
        print("[Speech] Stopped listening")
    }
    
    /// Toggle listening state
    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }
}
