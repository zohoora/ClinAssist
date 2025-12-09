import SwiftUI

/// View for updating the local drug database
struct DatabaseUpdateView: View {
    @ObservedObject var builder: DrugDatabaseBuilder
    @State private var showConfirmation = false
    
    private let database = DrugDatabase.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drug Database")
                        .font(.headline)
                    
                    if database.isDatabaseReady {
                        Text("Ready")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("Not Built")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            Divider()
            
            // Status info
            VStack(alignment: .leading, spacing: 12) {
                if database.isDatabaseReady {
                    HStack {
                        Label("\(database.getDrugCount()) drugs", systemImage: "pills")
                        Spacer()
                        Label("\(database.getVariantCount()) variants", systemImage: "list.bullet")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    
                    if let lastUpdate = database.lastUpdateDate {
                        HStack {
                            Text("Last updated:")
                                .foregroundColor(.secondary)
                            Text(lastUpdate, style: .date)
                            Text("at")
                                .foregroundColor(.secondary)
                            Text(lastUpdate, style: .time)
                        }
                        .font(.system(size: 12))
                    }
                } else {
                    Text("The drug database has not been built yet. Click the button below to download and build the database from Health Canada, ODB, and NIHB data sources.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal)
            
            // Progress section (when building)
            if builder.isBuilding {
                VStack(spacing: 12) {
                    ProgressView(value: builder.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text(builder.currentPhase.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text(builder.statusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    HStack {
                        Text("Drugs: \(builder.drugsProcessed)")
                        Spacer()
                        Text("Variants: \(builder.variantsProcessed)")
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            // Error message
            if let error = builder.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                .padding(.horizontal)
            }
            
            // Success message
            if builder.currentPhase == .complete && !builder.isBuilding {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Database updated successfully!")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            // Action buttons
            HStack {
                if database.isDatabaseReady && !builder.isBuilding {
                    Button("Rebuild Database") {
                        showConfirmation = true
                    }
                    .buttonStyle(.bordered)
                } else if !builder.isBuilding {
                    Button("Build Database") {
                        Task {
                            await builder.buildDatabase()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 450, height: 280)
        .alert("Rebuild Database?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Rebuild") {
                Task {
                    await builder.buildDatabase()
                }
            }
        } message: {
            Text("This will download all drug data from Health Canada and rebuild the local database. This may take 5-10 minutes.")
        }
    }
}

#Preview {
    DatabaseUpdateView(builder: DrugDatabaseBuilder())
}

