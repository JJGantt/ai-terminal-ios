import Foundation
import AVFoundation
import UIKit
import AudioToolbox

class VoiceRecorder: ObservableObject {
    enum State { case idle, recording, transcribing }

    @Published var state: State = .idle
    @Published var autoStopEnabled: Bool = UserDefaults.standard.object(forKey: "voiceAutoStop") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoStopEnabled, forKey: "voiceAutoStop") }
    }
    @Published var autoStopSeconds: Double = {
        let v = UserDefaults.standard.double(forKey: "voiceAutoStopSeconds")
        return v > 0 ? v : 3.0
    }() {
        didSet { UserDefaults.standard.set(autoStopSeconds, forKey: "voiceAutoStopSeconds") }
    }

    private var recorder: AVAudioRecorder?
    private var startTime: Date?
    private let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("phone-voice.wav")

    // Silence detection
    private var meteringTimer: Timer?
    private var baselineSamples: [Float] = []
    private var baseline: Float = -160
    private var baselineEstablished = false
    private var silenceStart: Date?
    private let baselineWindow: TimeInterval = 0.5  // seconds to sample baseline
    private let silenceMarginDB: Float = 8           // dB above baseline = still "silence"

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
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            AudioServicesPlaySystemSound(1113)
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .default, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.record()
            startTime = Date()
            state = .recording

            // Reset silence detection state
            baselineSamples = []
            baseline = -160
            baselineEstablished = false
            silenceStart = nil

            // Start metering timer for silence detection
            if autoStopEnabled {
                startMetering()
            }
        } catch {
            print("[VoiceRecorder] start error: \(error)")
        }
    }

    func stop() {
        guard state == .recording, let startTime else { return }
        stopMetering()
        let duration = Date().timeIntervalSince(startTime)
        recorder?.stop()
        recorder = nil
        state = .transcribing
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AudioServicesPlaySystemSound(1114)
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
        stopMetering()
        recorder?.stop()
        recorder = nil
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Silence Detection

    private func startMetering() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkAudioLevel()
        }
    }

    private func stopMetering() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }

    private func checkAudioLevel() {
        guard let recorder, state == .recording else { return }
        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)  // dB, -160 to 0

        let elapsed = -(startTime?.timeIntervalSinceNow ?? 0)

        // Phase 1: Establish baseline from ambient noise
        if !baselineEstablished {
            baselineSamples.append(level)
            if elapsed >= baselineWindow {
                baseline = baselineSamples.reduce(0, +) / Float(baselineSamples.count)
                baselineEstablished = true
                print("[VoiceRecorder] baseline established: \(String(format: "%.1f", baseline)) dB (\(baselineSamples.count) samples)")
            }
            return
        }

        // Phase 2: Detect silence (level near baseline)
        let isSilent = level < (baseline + silenceMarginDB)

        if isSilent {
            if silenceStart == nil {
                silenceStart = Date()
            } else if let start = silenceStart, Date().timeIntervalSince(start) >= autoStopSeconds {
                print("[VoiceRecorder] auto-stop: \(String(format: "%.1f", autoStopSeconds))s silence detected")
                stop()
            }
        } else {
            silenceStart = nil
        }
    }
}
