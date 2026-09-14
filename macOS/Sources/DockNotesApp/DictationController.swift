import AVFoundation
import Foundation
import Speech

@MainActor
final class DictationController: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle(locale: Locale, onTranscript: @escaping @MainActor (String) -> Void) {
        if isRecording {
            stop()
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.errorMessage = "Speech recognition permission was not granted."
                    return
                }
                self.start(locale: locale, onTranscript: onTranscript)
            }
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
    }

    private func start(locale: Locale, onTranscript: @escaping @MainActor (String) -> Void) {
        errorMessage = nil
        let recognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is currently unavailable."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            input.removeTap(onBus: 0)
            errorMessage = error.localizedDescription
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let text = result?.bestTranscription.formattedString, !text.isEmpty {
                    onTranscript(text)
                }
                if error != nil || result?.isFinal == true {
                    self?.stop()
                }
            }
        }
    }
}
