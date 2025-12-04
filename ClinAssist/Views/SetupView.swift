import SwiftUI

struct SetupView: View {
    @ObservedObject var configManager: ConfigManager
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            // Title
            VStack(spacing: 8) {
                Text("Welcome to ClinAssist")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Configuration Required")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Error message if present
            if let error = configManager.configError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                Text("Please create a config file at:")
                    .font(.subheadline)
                
                Text("~/Dropbox/livecode_records/config.json")
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                
                Text("Required format:")
                    .font(.subheadline)
                    .padding(.top, 8)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(sampleConfig)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            .cornerRadius(12)
            
            // Actions
            HStack(spacing: 12) {
                Button(action: {
                    configManager.createSampleConfig()
                    openConfigFolder()
                }) {
                    Label("Create Sample Config", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
            
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var sampleConfig: String {
        """
        {
          "openrouter_api_key": "sk-or-...",
          "deepgram_api_key": "...",
          "model": "openai/gpt-4.1",
          "timing": {
            "transcription_interval_seconds": 10,
            "helper_update_interval_seconds": 20,
            "soap_update_interval_seconds": 30
          }
        }
        """
    }
    
    private func openConfigFolder() {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Dropbox")
            .appendingPathComponent("livecode_records")
        
        NSWorkspace.shared.open(configPath)
    }
}

#Preview {
    SetupView(
        configManager: ConfigManager(),
        onRetry: { print("Retry") }
    )
    .frame(width: 380, height: 700)
}

