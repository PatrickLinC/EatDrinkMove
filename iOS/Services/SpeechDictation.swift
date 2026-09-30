import AVFoundation
import Speech

/// 用說的輸入：把麥克風的聲音即時轉成繁體中文文字（支援時在手機上辨識，不上傳）
@MainActor
final class SpeechDictation: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        guard !isRecording else { return }
        errorMessage = nil
        guard await Self.requestPermissions() else {
            errorMessage = "需要允許麥克風和語音辨識才能用說的，可以到「設定」開啟，或先用打字。"
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "語音辨識暫時不能用，可以先用打字。"
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request

            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0),
                             block: Self.tap(appendingTo: request))
            engine.prepare()
            try engine.start()

            transcript = ""
            isRecording = true
            task = recognizer.recognitionTask(with: request, resultHandler: Self.handler(for: self))
        } catch {
            errorMessage = "沒辦法開始錄音：\(error.localizedDescription)"
            stop()
        }
    }

    /// 停止收音；辨識會把最後一段整理完再結束
    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func receive(text: String?, finished: Bool) {
        if let text, !text.isEmpty { transcript = text }
        if finished {
            task = nil
            if isRecording { stop() }
        }
    }

    // 收音與辨識的回呼在背景執行緒，所以在 MainActor 以外建立

    nonisolated private static func tap(appendingTo request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    nonisolated private static func handler(for owner: SpeechDictation) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak owner] result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in owner?.receive(text: text, finished: finished) }
        }
    }

    private static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
