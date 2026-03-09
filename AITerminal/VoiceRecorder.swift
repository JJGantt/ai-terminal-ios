import Foundation
import AVFoundation
import UIKit
import AudioToolbox

class VoiceRecorder: ObservableObject {
    enum State { case idle, recording, transcribing }

    @Published var state: State = .idle

    private var recorder: AVAudioRecorder?
    private var startTime: Date?
    private let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("phone-voice.wav")

    var onComplete: ((Data, Double) -> Void)?

    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func start() {
        guard state == .idle else { return }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            // Feedback before audio session activates (session mutes output)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            AudioServicesPlaySystemSound(1113) // JBL_Begin
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .default, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder?.record()
            startTime = Date()
            state = .recording
        } catch {
            print("[VoiceRecorder] start error: \(error)")
        }
    }

    func stop() {
        guard state == .recording, let startTime else { return }
        let duration = Date().timeIntervalSince(startTime)
        recorder?.stop()
        recorder = nil
        state = .transcribing
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AudioServicesPlaySystemSound(1114) // JBL_Confirm
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        DispatchQueue.global().async {
            if let data = try? Data(contentsOf: self.fileURL) {
                DispatchQueue.main.async {
                    self.onComplete?(data, duration)
                    self.state = .idle
                }
            } else {
                DispatchQueue.main.async { self.state = .idle }
            }
        }
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
