//
//  ContentView.swift
//  VisionClaw
//
//  Created by Jessie Hua on 2/27/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message")
                }

            StreamingView()
                .tabItem {
                    Label("Stream", systemImage: "video")
                }
        }
    }
}

// MARK: - Streaming View

struct StreamingView: View {
    @StateObject private var viewModel = SessionViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()

                // Status indicator
                StatusBadge(state: viewModel.connectionState)

                // Glasses connection indicator
                if viewModel.isStreaming {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(viewModel.glassesConnected ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(viewModel.glassesConnected ? "Glasses Connected" : "Waiting for Glasses...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Main toggle button
                Button(action: { viewModel.toggleSession() }) {
                    Text(viewModel.isStreaming ? "Stop Streaming" : "Start Streaming")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(viewModel.isStreaming ? Color.red : Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 40)

                // Server info
                Text("Server: \(viewModel.serverHost):\(viewModel.serverPort)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .navigationTitle("VisionClaw")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let state: ConnectionState

    var color: Color {
        switch state {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(state.rawValue)
                .font(.headline)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}
