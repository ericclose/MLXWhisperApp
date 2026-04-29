import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var transcriber = Transcriber()
    @StateObject private var modelManager = ModelManager()
    @StateObject private var systemMonitor = SystemMonitor()
    @StateObject private var historyManager = HistoryManager()
    
    @State private var selectedFileURL: URL? = nil
    @State private var currentFileName: String? = nil
    @State private var isHovering = false
    @State private var showingSettings = false
    var body: some View {
        NavigationView {
            SidebarView(historyManager: historyManager, systemMonitor: systemMonitor, transcriber: transcriber) { item in
                self.currentFileName = item.sourceFileName
                transcriber.state = .completed(item.text, item.segments)
            }
            MainView(transcriber: transcriber, 
                     modelManager: modelManager, 
                     selectedFileURL: $selectedFileURL, 
                     currentFileName: $currentFileName,
                     isHovering: $isHovering,
                     showingSettings: $showingSettings) { text, segments in
                let fileName = selectedFileURL?.lastPathComponent ?? "transcription"
                historyManager.addItem(text: text, segments: segments, sourceFileName: fileName)
                self.currentFileName = fileName
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: { transcriber.state = .idle; selectedFileURL = nil }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("New Task")
                    }
                    .foregroundColor(.blue)
                }
                .help("Start a new transcription")
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingSettings.toggle() }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .sheet(isPresented: $showingSettings) {
                    VStack(spacing: 0) {
                        SettingsView(transcriber: transcriber, modelManager: modelManager)
                        
                        Divider()
                        
                        HStack {
                            Spacer()
                            Button("Done") {
                                showingSettings = false
                            }
                            .buttonStyle(.borderedProminent)
                            .padding()
                        }
                    }
                }
            }
        }
    }
}

struct SidebarView: View {
    @ObservedObject var historyManager: HistoryManager
    @ObservedObject var systemMonitor: SystemMonitor
    @ObservedObject var transcriber: Transcriber
    let onSelect: (TranscriptionHistoryItem) -> Void
    
    @State private var searchText: String = ""
    @State private var isTodayExpanded = true
    @State private var isYesterdayExpanded = true
    @State private var isOlderExpanded = false
    
    @State private var selection = Set<UUID>()
    @State private var showingClearAlert = false
    @State private var showingDeleteAlert = false
    @State private var indicesToDelete: IndexSet?
    @State private var deleteTargetGroup: [TranscriptionHistoryItem]?
    
    var groupedHistory: [String: [TranscriptionHistoryItem]] {
        let calendar = Calendar.current
        var groups: [String: [TranscriptionHistoryItem]] = ["Today": [], "Yesterday": [], "Older": []]
        
        let filtered = searchText.isEmpty ? historyManager.history : 
                       historyManager.history.filter { $0.text.localizedCaseInsensitiveContains(searchText) || $0.sourceFileName.localizedCaseInsensitiveContains(searchText) }
        
        for item in filtered {
            if calendar.isDateInToday(item.date) {
                groups["Today"]?.append(item)
            } else if calendar.isDateInYesterday(item.date) {
                groups["Yesterday"]?.append(item)
            } else {
                groups["Older"]?.append(item)
            }
        }
        return groups
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search history...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 8)
            
            List(selection: $selection) {
                Section(header: 
                    HStack {
                        Text("History")
                        Spacer()
                        if !selection.isEmpty {
                            Button(action: { showingDeleteAlert = true }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Delete Selected")
                        }
                        
                        if !historyManager.history.isEmpty {
                            Button("Clear") {
                                showingClearAlert = true
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.red.opacity(0.8))
                        }
                    }
                ) {
                    if historyManager.history.isEmpty {
                        Text("No transcriptions yet.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 10)
                    } else {
                        let groups = groupedHistory
                        
                        if let today = groups["Today"], !today.isEmpty {
                            DisclosureGroup(isExpanded: $isTodayExpanded) {
                                ForEach(today) { item in
                                    HistoryCard(item: item, 
                                               isSelected: selection.contains(item.id),
                                               onSelect: { 
                                                   selection = [item.id]
                                                   onSelect(item) 
                                               })
                                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                }
                                .onDelete { indices in
                                    historyManager.deleteItems(at: indices, filteredItems: today)
                                }
                            } label: {
                                Text("Today").font(.caption.bold()).foregroundColor(.secondary)
                            }
                        }
                        
                        if let yesterday = groups["Yesterday"], !yesterday.isEmpty {
                            DisclosureGroup(isExpanded: $isYesterdayExpanded) {
                                ForEach(yesterday) { item in
                                    HistoryCard(item: item, 
                                               isSelected: selection.contains(item.id),
                                               onSelect: { 
                                                   selection = [item.id]
                                                   onSelect(item) 
                                               })
                                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                }
                                .onDelete { indices in
                                    historyManager.deleteItems(at: indices, filteredItems: yesterday)
                                }
                            } label: {
                                Text("Yesterday").font(.caption.bold()).foregroundColor(.secondary)
                            }
                        }
                        
                        if let older = groups["Older"], !older.isEmpty {
                            DisclosureGroup(isExpanded: $isOlderExpanded) {
                                ForEach(older) { item in
                                    HistoryCard(item: item, 
                                               isSelected: selection.contains(item.id),
                                               onSelect: { 
                                                   selection = [item.id]
                                                   onSelect(item) 
                                               })
                                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                }
                                .onDelete { indices in
                                    historyManager.deleteItems(at: indices, filteredItems: older)
                                }
                            } label: {
                                Text("Older").font(.caption.bold()).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .alert("Clear All History?", isPresented: $showingClearAlert) {
                Button("Clear All", role: .destructive) {
                    historyManager.clearAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all transcription records and the local data file. This action cannot be undone.")
            }
            .alert("Delete Selected Items?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if !selection.isEmpty {
                        historyManager.history.removeAll { selection.contains($0.id) }
                        selection.removeAll()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete the selected transcription records?")
            }
            
            // Dashboard
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                Text("Dashboard")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                MetricView(title: "CPU Load", 
                           value: systemMonitor.cpuUsage, 
                           label: String(format: "%.0f%%", systemMonitor.cpuUsage),
                           color: .orange)
                
                MetricView(title: "Memory", 
                           value: systemMonitor.memoryUsage, 
                           label: String(format: "%.1f / %.0f GB", systemMonitor.memoryUsedGB, systemMonitor.memoryTotalGB),
                           color: .blue)
                
                MetricView(title: "GPU Usage", 
                           value: systemMonitor.gpuUsage, 
                           label: String(format: "%.0f%%", systemMonitor.gpuUsage),
                           color: .purple)
            }
            .padding(.bottom, 20)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .frame(minWidth: 200)
    }
}

struct HistoryCard: View {
    let item: TranscriptionHistoryItem
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.sourceFileName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Spacer()
                
                Text(item.date, style: .time)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            
            Text(item.text)
                .font(.caption)
                .lineLimit(2)
                .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : (isHovering ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor)))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            onSelect()
        }
    }
}

struct MetricView: View {
    let title: String
    let value: Double
    let label: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text(label)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: min(value, 100), total: 100)
                .progressViewStyle(LinearProgressViewStyle(tint: color))
                .scaleEffect(x: 1, y: 0.5, anchor: .center)
        }
        .padding(.horizontal)
    }
}

extension TranscriberState {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

struct MainView: View {
    @ObservedObject var transcriber: Transcriber
    @ObservedObject var modelManager: ModelManager
    @Binding var selectedFileURL: URL?
    @Binding var currentFileName: String?
    @Binding var isHovering: Bool
    @Binding var showingSettings: Bool
    
    var onComplete: (String, [TranscriptionSegment]) -> Void
    
    var body: some View {
        VStack {
            if case .completed(let text, let segments) = transcriber.state {
                ResultView(transcriber: transcriber, text: text, segments: segments, sourceFileName: currentFileName ?? "transcription")
                    .onAppear {
                        onComplete(text, segments)
                        modelManager.checkDownloadedModels()
                    }
            } else if case .error(let msg) = transcriber.state {
                ErrorView(message: msg, resetAction: { transcriber.state = .idle })
            } else if transcriber.state != .idle {
                ProgressView()
                if case .transcribing(let msg) = transcriber.state {
                    Text(msg).padding(.top)
                    
                    if let percent = transcriber.downloadPercent {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: percent, total: 100.0)
                                .progressViewStyle(LinearProgressViewStyle())
                            
                            HStack {
                                Text("\(Int(percent))%")
                                Spacer()
                                Text(transcriber.downloadSpeed)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                        .padding(.horizontal)
                    }
                    
                    if let transPercent = transcriber.transcriptionPercent {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: transPercent, total: 100.0)
                                .progressViewStyle(LinearProgressViewStyle())
                            
                            HStack {
                                Text("\(Int(transPercent))%")
                                Spacer()
                            }
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                        .padding(.horizontal)
                    }
                } else if case .extractingAudio = transcriber.state {
                    Text("Extracting Audio...").padding(.top)
                }
                Button("Cancel") {
                    transcriber.cancel()
                }
                .padding(.top)
            } else {
                DropZoneView(selectedFileURL: $selectedFileURL, isHovering: $isHovering)
                
                if let url = selectedFileURL {
                    Text("Selected: \(url.lastPathComponent)")
                        .padding()
                    Button("Start Transcription") {
                        transcriber.transcribe(fileURL: url, modelID: modelManager.selectedModel)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .padding()
    }
}

struct DropZoneView: View {
    @Binding var selectedFileURL: URL?
    @Binding var isHovering: Bool
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audiovisualContent, .movie, .audio, .video]
        if panel.runModal() == .OK, let url = panel.url {
            DispatchQueue.main.async {
                self.selectedFileURL = url
            }
        }
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(isHovering ? Color.accentColor : Color.secondary, style: StrokeStyle(lineWidth: 2, dash: [10]))
                .background(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
            
            VStack {
                Image(systemName: "arrow.down.doc")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("Drop Video/Audio file here")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.top, 5)
            }
        }
        .frame(height: 200)
        .contentShape(Rectangle()) // Make the whole area clickable
        .onTapGesture {
            selectFile()
        }
        .onDrop(of: [UTType.audiovisualContent.identifier, UTType.audio.identifier, UTType.movie.identifier], isTargeted: $isHovering) { providers in
            guard let provider = providers.first else { return false }
            
            // It's safer to load the file representation to ensure we get a readable local file URL.
            // The provided URL is temporary and only valid within the closure, so we must copy it.
            if let typeID = provider.registeredTypeIdentifiers.first {
                provider.loadFileRepresentation(forTypeIdentifier: typeID) { url, error in
                    guard let tempURL = url else { return }
                    let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + tempURL.lastPathComponent)
                    try? FileManager.default.removeItem(at: destURL)
                    do {
                        try FileManager.default.copyItem(at: tempURL, to: destURL)
                        DispatchQueue.main.async {
                            self.selectedFileURL = destURL
                        }
                    } catch {
                        print("Failed to copy dropped file: \(error)")
                    }
                }
            }
            return true
        }
    }
}

struct ResultView: View {
    @ObservedObject var transcriber: Transcriber
    let text: String
    let segments: [TranscriptionSegment]
    let sourceFileName: String
    
    @State private var displayFormat: String = "srt"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Transcription Result", systemImage: "text.quote")
                    .font(.title2.bold())
                
                Spacer()
                
                Picker("", selection: $displayFormat) {
                    Text("SRT").tag("srt")
                    Text("VTT").tag("vtt")
                    Text("Plain Text").tag("txt")
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if displayFormat == "txt" {
                            Text(text)
                                .font(.body)
                                .lineSpacing(6)
                                .padding()
                        } else {
                            SubtitleListView(segments: segments, format: displayFormat)
                                .padding()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(NSColor.textBackgroundColor))
                .textSelection(.enabled)
                
                // Filename indicator footer
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.blue)
                    Text(sourceFileName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(segments.count) segments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            }
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            
            HStack {
                Spacer()
                Button(action: { export(type: displayFormat) }) {
                    Label("Export as \(displayFormat.uppercased())", systemImage: "square.and.arrow.down.fill")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding()
    }
    
    private func export(type: String) {
        let content = (type == "srt") ? SubtitleFormatter.convertToSRT(segments: segments) :
                      (type == "vtt") ? SubtitleFormatter.convertToVTT(segments: segments) : text
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [type == "txt" ? .plainText : .text]
        
        let baseName = (sourceFileName as NSString).deletingPathExtension
        savePanel.nameFieldStringValue = "\(baseName).\(type)"
        
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Export failed: \(error)")
                }
            }
        }
    }
    
}

struct ErrorView: View {
    let message: String
    let resetAction: () -> Void
    
    var body: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.red)
            Text("An error occurred")
                .font(.headline)
                .padding(.top, 5)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .textSelection(.enabled)
            
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message, forType: .string)
            }) {
                Label("Copy Error Message", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 4)
            
            Button("Try Again", action: resetAction)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var transcriber: Transcriber
    @ObservedObject var modelManager: ModelManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Model Selection")
                    .font(.headline)
                
                Picker("Model", selection: $modelManager.selectedModel) {
                    if modelManager.availableModels.isEmpty {
                        Text("Loading models...").tag(modelManager.selectedModel)
                    } else {
                        ForEach(modelManager.availableModels, id: \.self) { model in
                            HStack {
                                if modelManager.downloadedModels.contains(model) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                                Text("\(model) (\(modelManager.displaySize(for: model)))")
                                
                                if modelManager.downloadedModels.contains(model) {
                                    Spacer()
                                    Button(action: { modelManager.deleteModel(model) }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .tag(model)
                        }
                    }
                }
                .pickerStyle(.menu)
                
                HStack {
                    TextField("Custom HF ID", text: $modelManager.customModelInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        modelManager.addCustomModel()
                    }
                }
                
                Button(action: { modelManager.openModelsFolder() }) {
                    Label("Show Models in Finder", systemImage: "folder")
                }
                .buttonStyle(.link)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Inference Parameters")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature: \(transcriber.temperature, specifier: "%.1f")")
                        Spacer()
                    }
                    Slider(value: $transcriber.temperature, in: 0...1, step: 0.1)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Logprob Threshold: \(transcriber.logprobThreshold, specifier: "%.1f")")
                        Spacer()
                    }
                    Slider(value: $transcriber.logprobThreshold, in: -5...0, step: 0.1)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Compression Ratio: \(transcriber.compressionRatioThreshold, specifier: "%.1f")")
                        Spacer()
                    }
                    Slider(value: $transcriber.compressionRatioThreshold, in: 0...5, step: 0.1)
                }
            }
        }
        .padding(25)
        .frame(width: 420)
    }
}
struct SubtitleFormatter {
    static func formatTimestamp(_ seconds: Double, format: String) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        let milliseconds = Int(round((seconds - Double(totalSeconds)) * 1000))
        
        if format == "srt" {
            return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, min(999, milliseconds))
        } else {
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, min(999, milliseconds))
        }
    }
    
    static func convertToSRT(segments: [TranscriptionSegment]) -> String {
        var srt = ""
        for (index, segment) in segments.enumerated() {
            srt += "\(index + 1)\n"
            srt += "\(formatTimestamp(segment.start, format: "srt")) --> \(formatTimestamp(segment.end, format: "srt"))\n"
            srt += "\(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
        }
        return srt
    }
    
    static func convertToVTT(segments: [TranscriptionSegment]) -> String {
        var vtt = "WEBVTT\n\n"
        for segment in segments {
            vtt += "\(formatTimestamp(segment.start, format: "vtt")) --> \(formatTimestamp(segment.end, format: "vtt"))\n"
            vtt += "\(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
        }
        return vtt
    }
}

struct SubtitleListView: View {
    let segments: [TranscriptionSegment]
    let format: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(.blue.opacity(0.8))
                            .frame(width: 30, alignment: .leading)
                        
                        Text(SubtitleFormatter.formatTimestamp(segment.start, format: format) + " ➞ " + SubtitleFormatter.formatTimestamp(segment.end, format: format))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.orange.opacity(0.9))
                    }
                    
                    Text(segment.text)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if index < segments.count - 1 {
                    Divider().opacity(0.3)
                }
            }
        }
    }
}
