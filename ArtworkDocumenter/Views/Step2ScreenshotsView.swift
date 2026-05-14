import SwiftUI
import ScreenCaptureKit

struct Step2ScreenshotsView: View {
    @Environment(ProjectState.self) private var state
    @State private var capture = ScreenCaptureManager()

    @State private var captureMode: CaptureSource = .display
    @State private var selectedDisplayIndex: Int = 0
    @State private var selectedWindowIndex: Int = 0
    @State private var isCapturing = false
    @State private var errorMessage: String? = nil

    enum CaptureSource { case display, window }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Capture Screenshots")
                    .font(.title2.bold())
                Text("Capture 3–5 screenshots of your artwork. Choose a display or a specific window.")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 36)
            .padding(.top, 32)
            .padding(.bottom, 20)

            // Source picker + capture button
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
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
                            Text("No windows found. Make sure the app you want to capture is open.")
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

                    HStack {
                        Button {
                            Task { await takeScreenshot() }
                        } label: {
                            if isCapturing {
                                Label("Capturing…", systemImage: "camera.fill")
                            } else {
                                Label("Capture Screenshot", systemImage: "camera")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCapturing || state.screenshots.count >= 5 || !capture.permissionGranted)

                        if isCapturing { ProgressView().scaleEffect(0.75).padding(.leading, 4) }

                        Spacer()

                        Text("\(state.screenshots.count) / 5")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(state.screenshots.count >= 3 ? Color.green : Color.secondary)
                    }

                    if let msg = errorMessage {
                        Text(msg).font(.caption).foregroundStyle(.red)
                    }

                    if capture.permissionDenied { permissionBanner }
                }
            }
            .padding(.horizontal, 36)

            // Screenshot grid (no scroll — all visible on screen)
            if state.screenshots.isEmpty {
                Spacer()
                Text("No screenshots yet — capture at least 3 to continue.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Array(state.screenshots.enumerated()), id: \.offset) { idx, url in
                        ScreenshotThumbnail(url: url, index: idx + 1) {
                            retake(at: idx)
                        }
                    }
                }
                .padding(.horizontal, 36)
                .padding(.top, 20)

                Spacer(minLength: 0)
            }

            // Nav
            Divider()
            HStack {
                Button("Back") { state.currentStep = 1 }
                    .buttonStyle(.bordered)
                Spacer()
                if state.screenshots.count < 3 {
                    Text("Capture \(3 - state.screenshots.count) more to continue")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Continue to Recording") { state.currentStep = 3 }
                    .buttonStyle(.borderedProminent)
                    .disabled(!state.canProceedToStep3)
            }
            .padding(32)
        }
        .task { await loadContent() }
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield").foregroundStyle(.orange)
            Text("Screen Recording was denied. Enable ArtworkDocumenter in System Settings → Privacy & Security → Screen Recording, then relaunch.")
                .font(.caption).foregroundStyle(.orange)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadContent() async {
        await capture.loadAvailableContent()
        if !capture.permissionGranted && !capture.permissionDenied {
            errorMessage = "Waiting for screen recording permission…"
        } else {
            errorMessage = nil
        }
    }

    private func takeScreenshot() async {
        isCapturing = true
        errorMessage = nil
        do {
            let display = captureMode == .display ? capture.availableDisplays[safe: selectedDisplayIndex] : nil
            let window  = captureMode == .window  ? capture.availableWindows[safe: selectedWindowIndex]  : nil
            let image = try await capture.captureScreenshot(display: display, window: window)
            let index    = state.screenshots.count + 1
            let filename = String(format: "screenshot_%02d.png", index)
            let url      = state.outputDir!.appendingPathComponent(filename)
            try capture.saveScreenshot(image, to: url)
            state.screenshots.append(url)
        } catch {
            errorMessage = error.localizedDescription
        }
        isCapturing = false
    }

    private func retake(at index: Int) {
        let url = state.screenshots.remove(at: index)
        try? FileManager.default.removeItem(at: url)
        for (i, oldURL) in state.screenshots.enumerated() {
            let newURL = state.outputDir!.appendingPathComponent(String(format: "screenshot_%02d.png", i + 1))
            if oldURL.path != newURL.path {
                try? FileManager.default.moveItem(at: oldURL, to: newURL)
                state.screenshots[i] = newURL
            }
        }
    }
}

// MARK: - Thumbnail

struct ScreenshotThumbnail: View {
    let url: URL
    let index: Int
    let onRetake: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(maxWidth: .infinity, maxHeight: 130)
            }
            HStack {
                Text("Shot \(index)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Retake", action: onRetake)
                    .font(.caption).buttonStyle(.borderless).foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Safe subscript (shared utility)

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
