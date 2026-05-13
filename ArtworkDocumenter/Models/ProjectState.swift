import Foundation
import Observation

@Observable
@MainActor
final class ProjectState {
    var title: String = ""
    var conceptual: String = ""
    var technical: String = ""
    var url: String = ""
    var outputDir: URL? = nil

    var screenshots: [URL] = []

    var recordingURL: URL? = nil
    var isRecording: Bool = false
    var recordingFinished: Bool = false
    var elapsedSeconds: Int = 0

    var currentStep: Int = 1

    var canProceedToStep2: Bool {
        !title.isEmpty && !conceptual.isEmpty && !technical.isEmpty
    }

    var canProceedToStep3: Bool {
        screenshots.count >= 3
    }

    func reset() {
        title = ""
        conceptual = ""
        technical = ""
        url = ""
        outputDir = nil
        screenshots = []
        recordingURL = nil
        isRecording = false
        recordingFinished = false
        elapsedSeconds = 0
        currentStep = 1
    }
}
