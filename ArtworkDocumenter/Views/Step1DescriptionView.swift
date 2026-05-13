import SwiftUI

struct Step1DescriptionView: View {
    @Environment(ProjectState.self)  private var state
    @Environment(ExportSettings.self) private var settings
    @State private var showError   = false
    @State private var errorText   = ""
    @State private var showExportSettings = false

    var body: some View {
        @Bindable var state    = state
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project Documentation")
                        .font(.title2.bold())
                    Text("Provide a written description of your screen-based artwork.")
                        .foregroundStyle(.secondary)
                }

                // Title
                formField(label: "Project Title", icon: "textformat") {
                    TextField("Enter the title of your project", text: $state.title)
                        .textFieldStyle(.roundedBorder)
                }

                // Conceptual
                formField(label: "Conceptual Underpinnings", icon: "brain",
                          hint: "Describe the ideas, themes, and concepts behind your work.") {
                    TextEditor(text: $state.conceptual)
                        .font(.body).frame(minHeight: 100)
                        .padding(4)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.35)))
                }

                // Technical
                formField(label: "Technical Attributes", icon: "cpu",
                          hint: "Describe the tools, languages, platforms, and technical details.") {
                    TextEditor(text: $state.technical)
                        .font(.body).frame(minHeight: 100)
                        .padding(4)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.35)))
                }

                // URL
                formField(label: "Project URL (optional)", icon: "link") {
                    TextField("https://", text: $state.url)
                        .textFieldStyle(.roundedBorder)
                }

                // ── Export Settings ──────────────────────────────────────
                DisclosureGroup(isExpanded: $showExportSettings) {
                    VStack(alignment: .leading, spacing: 20) {
                        exportVideoSection(settings: $settings)
                        Divider()
                        exportImageSection(settings: $settings)
                    }
                    .padding(.top, 12)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.secondary)
                        Text("Export Settings")
                            .font(.headline)
                        Spacer()
                        summaryLabel
                    }
                }
                .padding(16)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Continue
                HStack {
                    Spacer()
                    Button("Save & Continue") { saveAndContinue() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!state.canProceedToStep2)
                }
            }
            .padding(36)
        }
        .alert("Could Not Save", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorText)
        }
    }

    // MARK: - Summary chip (shown when collapsed)

    private var summaryLabel: some View {
        HStack(spacing: 6) {
            chip(settings.videoResolution.rawValue)
            chip(settings.videoCodec.rawValue)
            chip(settings.videoContainer.rawValue)
            chip(settings.imageFormat.rawValue)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
            .foregroundStyle(Color.accentColor)
    }

    // MARK: - Video export section

    @ViewBuilder
    private func exportVideoSection(settings: Bindable<ExportSettings>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Video", systemImage: "video").font(.subheadline.bold())

            settingsRow(label: "Codec") {
                Picker("Codec", selection: settings.videoCodec) {
                    ForEach(ExportSettings.VideoCodec.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            settingsRow(label: "Resolution") {
                Picker("Resolution", selection: settings.videoResolution) {
                    ForEach(ExportSettings.VideoResolution.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            settingsRow(label: "Container") {
                Picker("Container", selection: settings.videoContainer) {
                    ForEach(ExportSettings.VideoContainer.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            settingsRow(label: "Frame Rate") {
                Picker("Frame Rate", selection: settings.videoFrameRate) {
                    ForEach(ExportSettings.FrameRate.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Note about H.265 file size benefit
            if settings.videoCodec.wrappedValue == .hevc {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("H.265 produces smaller files at equivalent quality. Requires macOS 10.13+ to play back.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Image export section

    @ViewBuilder
    private func exportImageSection(settings: Bindable<ExportSettings>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Screenshots", systemImage: "photo").font(.subheadline.bold())

            settingsRow(label: "Format") {
                Picker("Format", selection: settings.imageFormat) {
                    ForEach(ExportSettings.ImageFormat.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if settings.imageFormat.wrappedValue == .jpeg {
                settingsRow(label: "Quality") {
                    Picker("Quality", selection: settings.jpegQuality) {
                        ForEach(ExportSettings.JPEGQuality.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("JPEG produces smaller files but uses lossy compression. PNG is lossless and recommended for archival.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func formField<Content: View>(label: String, icon: String, hint: String? = nil,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon).font(.headline)
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
    }

    @ViewBuilder
    private func settingsRow<Content: View>(label: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            content()
        }
    }

    // MARK: - Save

    private func saveAndContinue() {
        do {
            let safe = state.title
                .replacingOccurrences(of: "[^a-zA-Z0-9 \\-_]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            let folderName = safe.isEmpty ? "Untitled Documentation" : "\(safe) Documentation"
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
                .appendingPathComponent(folderName)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            state.outputDir = dir

            var content = "TITLE: \(state.title)\n\n"
            content += "CONCEPTUAL:\n\(state.conceptual)\n\n"
            content += "TECHNICAL:\n\(state.technical)\n"
            if !state.url.isEmpty { content += "\nURL: \(state.url)\n" }
            try content.write(to: dir.appendingPathComponent("description.txt"),
                              atomically: true, encoding: .utf8)
            state.currentStep = 2
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
    }
}
