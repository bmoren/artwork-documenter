import SwiftUI
import CoreGraphics

struct ContentView: View {
    @Environment(ProjectState.self) private var state
    // Check permission synchronously at startup; SetupView handles the
    // request flow and calls onGranted() when the user approves.
    @State private var permissionGranted: Bool = CGPreflightScreenCaptureAccess()

    var body: some View {
        if permissionGranted {
            mainFlow
        } else {
            SetupView(onGranted: { permissionGranted = true })
                .frame(minWidth: 560, minHeight: 520)
        }
    }

    private var mainFlow: some View {
        VStack(spacing: 0) {
            StepIndicator(currentStep: state.currentStep)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(.windowBackground)

            Divider()

            Group {
                switch state.currentStep {
                case 1: Step1DescriptionView()
                case 2: Step2ScreenshotsView()
                case 3: Step3RecordingView()
                default: Step1DescriptionView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 580)
    }
}

// MARK: - Step indicator

struct StepIndicator: View {
    let currentStep: Int
    private let steps = ["Description", "Screenshots", "Screen Recording"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, label in
                let step    = idx + 1
                let isDone  = step < currentStep
                let isActive = step == currentStep

                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(isDone || isActive ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 26, height: 26)
                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.caption.bold()).foregroundStyle(.white)
                        } else {
                            Text("\(step)")
                                .font(.caption.bold())
                                .foregroundStyle(isActive ? .white : .secondary)
                        }
                    }
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundStyle(isActive ? .primary : .secondary)
                }

                if step < steps.count {
                    Rectangle()
                        .fill(isDone ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 2)
                        .padding(.horizontal, 12)
                }
            }
        }
    }
}
