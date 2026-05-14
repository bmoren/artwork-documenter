import SwiftUI
import CoreGraphics

struct SetupView: View {
    /// Called once permission is confirmed so ContentView can swap in the main flow.
    let onGranted: () -> Void

    @State private var status: PermissionStatus = .notDetermined
    @State private var pollTimer: Timer? = nil

    enum PermissionStatus {
        case notDetermined  // haven't asked yet
        case waiting        // asked; polling for user action in System Settings
        case granted
        case denied         // previously denied; must go to System Settings manually
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Branding
            VStack(spacing: 16) {
                Image(systemName: "rectangle.inset.filled.and.person.filled")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 6) {
                    Text("Artwork Documenter")
                        .font(.largeTitle.bold())
                    Text("A three-step tool for documenting screen-based artworks.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer().frame(height: 40)

            // What the app does
            HStack(alignment: .top, spacing: 0) {
                stepPill(number: "1", icon: "text.alignleft",     label: "Write a description")
                stepPill(number: "2", icon: "camera",              label: "Capture screenshots")
                stepPill(number: "3", icon: "record.circle",       label: "Record video + audio")
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 40)

            // Permission card
            GroupBox {
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: statusIcon)
                            .font(.title3)
                            .foregroundStyle(statusColor)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Screen Recording Permission")
                            .font(.headline)
                        Text("Required to capture screenshots and video with system audio. This data stays entirely on your Mac — nothing is uploaded.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer().frame(height: 4)

                        switch status {
                        case .notDetermined:
                            Button("Grant Access…") { requestPermission() }
                                .buttonStyle(.borderedProminent)

                        case .waiting:
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.8)
                                Text("Waiting — grant access in System Settings, then return here.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button("Open System Settings") { openPrivacySettings() }
                                .buttonStyle(.bordered)
                                .font(.caption)

                        case .denied:
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Permission was denied. Enable it manually:")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text("System Settings → Privacy & Security → Screen Recording → enable Artwork Documenter")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Open System Settings") { openPrivacySettings() }
                                    .buttonStyle(.bordered)
                            }

                        case .granted:
                            Label("Access granted", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(4)
            }
            .padding(.horizontal, 48)

            Spacer().frame(height: 32)

            // Continue button — only shown when granted
            if status == .granted {
                Button("Get Started") {
                    pollTimer?.invalidate()
                    onGranted()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .transition(.opacity.combined(with: .scale(0.95)))
            }

            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: status)
        .onAppear { checkCurrentStatus() }
        .onDisappear { pollTimer?.invalidate() }
    }

    // MARK: - Step pill

    private func stepPill(number: String, icon: String, label: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 90)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status appearance helpers

    private var statusIcon: String {
        switch status {
        case .notDetermined: return "shield"
        case .waiting:       return "clock"
        case .denied:        return "exclamationmark.shield"
        case .granted:       return "checkmark.shield.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .notDetermined: return .accentColor
        case .waiting:       return .orange
        case .denied:        return .red
        case .granted:       return .green
        }
    }

    // MARK: - Permission logic

    private func checkCurrentStatus() {
        if CGPreflightScreenCaptureAccess() {
            status = .granted
        }
        // If not granted yet, stay on .notDetermined until the user taps the button
    }

    private func requestPermission() {
        CGRequestScreenCaptureAccess()
        // macOS either shows a one-time dialog or opens System Settings.
        // Either way we start polling so we detect the grant automatically.
        status = .waiting
        startPolling()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { _ in
            MainActor.assumeIsolated {
                if CGPreflightScreenCaptureAccess() {
                    pollTimer?.invalidate()
                    status = .granted
                }
            }
        }
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        // Begin polling in case we aren't already
        if status != .waiting { status = .waiting }
        startPolling()
    }
}
