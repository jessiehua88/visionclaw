//
//  SettingsView.swift
//  VisionClaw
//
//  Created by Jessie Hua on 2/27/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("serverHost") private var serverHost: String = "10.9.50.189"
    @AppStorage("serverPort") private var serverPort: Int = 18789
    @AppStorage("serverPassword") private var serverPassword: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenClaw Server") {
                    HStack {
                        Text("IP Address")
                        Spacer()
                        TextField("127.0.0.1", text: $serverHost)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .autocorrectionDisabled()
                    }

                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("18789", value: $serverPort, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }

                    HStack {
                        Text("Password")
                        Spacer()
                        SecureField("Required", text: $serverPassword)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    Text("ws://\(serverHost):\(serverPort)/")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } header: {
                    Text("WebSocket URL")
                }

                Section("About") {
                    LabeledContent("App", value: "VisionClaw")
                    LabeledContent("Protocol", value: "Binary prefixed (0x01/0x02)")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
