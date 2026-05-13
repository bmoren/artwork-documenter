import SwiftUI
import ScreenCaptureKit
import AVKit
import UniformTypeIdentifiers

struct Step3RecordingView: View {
    @Environment(ProjectState.self)   private var state
    @Environment(ExportSettings.self) private var settings
    @State private var capture = ScreenCaptureManager()
    @State private var merger  = VideoMergeManager()

    @State private var captureMode: CaptureSource = .display
    @State private var selectedDisplayIndex: Int = 0
    @State private var selectedWindowIndex: Int  = 0

    @State private var timer: Timer? = nil
    @State private var errorMessage: String? = nil

    // Clip insertion
    @State private var clipURL: URL? = nil
    @State private var clipPosition: ClipPosition = .end
    @State private var mergeSuccess = false

    // Video player for the recording (shown after recording finishes)
    @State private var recordingPlayer: AVPlayer? = nil

    enum CaptureSource { case display, window }
    enum ClipPosition: String, CaseIterable {
        case start     = "Beginning"
        case end       = "End"
        case current   = "Current Position"
    }

    private var elapsedFormatted: String {
        let m = state.elapsedSeconds / 60
        let s = state.elapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Screen Recording")
                            .font(.title2.bold())
                        Text("Record 1–3 minutes of your artwork. System audio is captured automatically.")
                            .foregroundStyle(.secondary)
                    }

                    if state.recordingFinished {
                        doneSection
                    } else if state.isRecording {
                        activeRecordingSection
                    } else {
                        setupSection
                    }

                    if let msg = errorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(.red)
                            Text(msg).font(.caption).foregroundStyle(.red)
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(36)
            }

            Divider()
            HStack {
                Button("Back") { state.currentStep = 2 }
                    .buttonStyle(.bordered)
                    .disabled(state.isRecording)
                Spacer()
            }
            .padding(32)
        }
        .task { await capture.loadAvailableContent() }
        .onDisappear { timer?.invalidate() }
        .onChange(of: state.recordingFinished) { _, finished in
            if finished, let url = state.recordingURL {
                recordingPlayer = AVPlayer(url: url)
            }
        }
    }

    // MARK: - Setup

    private var setupSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Source", selection: $captureMode) {
                    Text("Full Display").tag(CaptureSource.display)
                    Text("Specific Window").tag(CaptureSource.window)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if captureMode == .display, capture.availableDisplays.count > 1 {
                    Picker("Display", selection: $selectedDisplayIndex) {
                        ForEach(capture.availableDisplays.indices, id: \.self) { i in
                            Text("Display \(i + 1)").tag(i)
                        }
                    }
                }

                if captureMode == .window {
                    if capture.availableWindows.isEmpty {
                        Text("No windows found. Open the app you want to record first.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Window", selection: $selectedWindowIndex) {
                            ForEach(capture.availableWindows.indices, id: \.self) { i in
                                let w = capture.availableWindows[i]
                                Text("\(w.owningApplication?.applicationName ?? "App")  —  \(w.title ?? "Window")")
                                    .tag(i)
                            }
                        }
                    }
                }

                Button {
                    Task { await startRecording() }
                } label: {
                    Label("Start Recording", systemImage: "record.circle.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(!capture.permissionGranted)

                if capture.permissionDenied {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.shield").foregroundStyle(.orange)
                        Text("Screen Recording was denied. Enable ArtworkDocumenter in System Settings → Privacy & Security → Screen Recording, then relaunch.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        } label: {
            Label("Recording Source", systemImage: "display").font(.headline)
        }
    }

    // MARK: - Active recording

    private var activeRecordingSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                        .opacity(state.elapsedSeconds % 2 == 0 ? 1 : 0.2)
                    Text("RECORDING")
                        .font(.caption.bold().smallCaps())
                        .foregroundStyle(.red)
                }
                Text(elapsedFormatted)
                    .font(.system(size: 80, weight: .ultraLight, design: .monospaced))
                    .monospacedDigit()
                if state.elapsedSeconds < 60 {
                    Text("Tip: aim for at least 1 minute")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("\(180 - state.elapsedSeconds)s remaining")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(Color.red.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Button {
                Task { await stopRecording() }
            } label: {
                Label("Stop Recording", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        }
    }

    // MARK: - Done

    private var doneSection: some View {
        VStack(alignment: .leading, spacing: 24) {

            // Success banner
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording saved!")
                        .font(.headline)
                    Text("Duration: \(elapsedFormatted)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Clip insertion with video preview
            clipInsertionSection

            Divider()

            // Output folder + finish
            VStack(alignment: .leading, spacing: 12) {
                if let dir = state.outputDir {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Output folder:").font(.caption.bold())
                        Text(dir.path)
                            .font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                HStack(spacing: 12) {
                    Button("Reveal in Finder") {
                        if let dir = state.outputDir {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Document Another Project") {
                        timer?.invalidate()
                        recordingPlayer?.pause()
                        recordingPlayer = nil
                        state.reset()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: - Clip insertion

    private var clipInsertionSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("You can insert an existing video clip into your recording.")
                    .font(.caption).foregroundStyle(.secondary)

                // Video player for the recording — scrub to find insertion point
                if let player = recordingPlayer {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Recording")
                            .font(.caption.bold())
                        VideoPlayerView(player: player)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                    }
                }

                // Clip picker
                HStack(spacing: 10) {
                    Button("Choose Video Clip…") { pickClip() }
                        .buttonStyle(.bordered)
                    if let url = clipURL {
                        Label(url.lastPathComponent, systemImage: "film")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }

                // Insertion position (only shown after clip is picked)
                if clipURL != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Insert clip at", selection: $clipPosition) {
                            ForEach(ClipPosition.allCases, id: \.self) { pos in
                                Text(pos.rawValue).tag(pos)
                            }
                        }
                        .pickerStyle(.segmented)

                        if clipPosition == .current {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text("Clip inserts at the scrubber position shown in the player above.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }

                        if mergeSuccess {
                            Label("Clip merged successfully!", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.green)
                        }

                        Button {
                            Task { await mergeClip() }
                        } label: {
                            if merger.isMerging {
                                Label("Merging…", systemImage: "arrow.triangle.merge")
                            } else {
                                Label("Merge into Recording", systemImage: "arrow.triangle.merge")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(merger.isMerging)
                    }
                }
            }
        } label: {
            Label("Insert Video Clip (Optional)", systemImage: "film.stack").font(.headline)
        }
    }

    // MARK: - Actions

    private func startRecording() async {
        errorMessage = nil
        guard let outputDir = state.outputDir else { return }
        let display = captureMode == .display ? capture.availableDisplays[safe: selectedDisplayIndex] : nil
        let window  = captureMode == .window  ? capture.availableWindows[safe: selectedWindowIndex]  : nil
        let outputURL = outputDir.appendingPathComponent("screen_recording.\(settings.fileExtension)")
        state.recordingURL = outputURL

        capture.onRecordingStarted = {
            state.isRecording = true
            startTimer()
        }
        capture.onRecordingFinished = {
            state.isRecording = false
            state.recordingFinished = true
            timer?.invalidate()
        }
        capture.onError = { msg in
            errorMessage = msg
            state.isRecording = false
            timer?.invalidate()
        }

        do {
            try await capture.startRecording(display: display, window: window, outputURL: outputURL, settings: settings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopRecording() async {
        do {
            try await capture.stopRecording()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startTimer() {
        state.elapsedSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            state.elapsedSeconds += 1
            if state.elapsedSeconds >= 180 {
                Task { await self.stopRecording() }
            }
        }
    }

    private func pickClip() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .video]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose a video clip to insert"
        if panel.runModal() == .OK {
            clipURL = panel.url
            mergeSuccess = false
        }
    }

    private func mergeClip() async {
        guard let clip = clipURL, let recording = state.recordingURL else { return }
        errorMessage = nil
        mergeSuccess = false

        // Pause the player so the file isn't locked during merge
        recordingPlayer?.pause()

        let position: InsertPosition
        switch clipPosition {
        case .start:   position = .start
        case .end:     position = .end
        case .current:
            // Read the current scrubber position from the AVPlayer
            let seconds = recordingPlayer?.currentTime().seconds ?? 0
            position = .timestamp(seconds.isNaN || seconds < 0 ? 0 : seconds)
        }

        do {
            try await merger.merge(mainURL: recording, clipURL: clip, position: position)
            mergeSuccess = true
            // Reload the player with the merged file
            recordingPlayer = AVPlayer(url: recording)
        } catch {
            errorMessage = "Merge failed: \(error.localizedDescription)"
        }
    }
}
