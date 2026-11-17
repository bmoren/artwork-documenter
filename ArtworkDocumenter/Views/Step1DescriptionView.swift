import SwiftUI
import AppKit

struct Step1DescriptionView: View {
    @Environment(ProjectState.self) private var state
    @State private var showError = false
    @State private var errorText = ""

    var body: some View {
        @Bindable var state = state

        VStack(alignment: .leading, spacing: 16) {

            // Save location picker
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save Location").font(.headline)
                    Text(saveLocationDisplay)
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Choose Folder…") { chooseSaveLocation() }
                    .buttonStyle(.bordered)
            }
            .padding(14)
            .background(Color.secondary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Title + URL — styled differently from the multiline editors below
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project Title").font(.headline)
                    TextField("Enter the title of your project", text: $state.title)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project URL").font(.headline)
                    TextField("https://", text: $state.url)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(14)
            .background(Color.secondary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Conceptual + Technical editors side by side — fills 75% of remaining height
            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Conceptual Underpinnings", systemImage: "brain").font(.headline)
                        TextEditor(text: $state.conceptual)
                            .font(.body)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(4)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.35)))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Technical Attributes", systemImage: "cpu").font(.headline)
                        TextEditor(text: $state.technical)
                            .font(.body)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(4)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.35)))
                    }
                }
                .frame(height: proxy.size.height * 0.75, alignment: .top)
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)

            // Continue
            HStack {
                Spacer()
                Button("Save & Continue") { saveAndContinue() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!state.canProceedToStep2)
            }
        }
        .padding(24)
        .alert("Could Not Save", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorText)
        }
    }

    // MARK: - Save location

    private var saveLocationDisplay: String {
        if let loc = state.saveLocation {
            return loc.path(percentEncoded: false)
        }
        return "~/Desktop (default)"
    }

    private func chooseSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select the folder where the project folder will be created"
        if panel.runModal() == .OK, let url = panel.url {
            state.saveLocation = url
        }
    }

    // MARK: - Save

    private func saveAndContinue() {
        do {
            let safe = state.title
                .replacingOccurrences(of: "[^a-zA-Z0-9 \\-_]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            let folderName = safe.isEmpty ? "Untitled Documentation" : "\(safe) Documentation"
            let base = state.saveLocation ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
            let dir = base.appendingPathComponent(folderName)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            state.outputDir = dir

            var content = "TITLE: \(state.title)\n\n"
            content += "CONCEPTUAL:\n\(state.conceptual)\n\n"
            content += "TECHNICAL:\n\(state.technical)\n"
            if !state.url.isEmpty { content += "\nURL: \(state.url)\n" }
            let textFilename = safe.isEmpty ? "description" : safe
            try content.write(to: dir.appendingPathComponent("\(textFilename).txt"),
                              atomically: true, encoding: .utf8)
            state.currentStep = 2
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
    }
}
