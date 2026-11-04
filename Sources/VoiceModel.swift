import AVFoundation
import CPitcheeCore
import Foundation
import Combine

@MainActor final class VoiceModel: ObservableObject {
    @Published var recording = false
    @Published var busy = false
    @Published var seconds = 0.0
    @Published var error: String?
    @Published private(set) var latest: Assessment?
    @Published var health: Double?
    @Published var pitches: [Double] = []
    @Published var spectrum: [Float] = []
    private let capture = AudioCapture()
    private let worker = DispatchQueue(label: "space.pitchee.analysis", qos: .userInitiated)
    private var timer: Timer?
    private let liveQueue = DispatchQueue(label: "space.pitchee.live", qos: .userInitiated)
    private let liveGate = DispatchSemaphore(value: 1)

    func start() async {
        guard !recording, !busy else { return }
        let allowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard allowed else { error = "请在 iOS 设置中允许 Pitchee 使用麦克风。"; return }
        do {
            seconds = 0; latest = nil; health = nil; pitches = []
            let queue = liveQueue, gate = liveGate
            capture.onFrame = { [weak self] pcm, rate in
                // A lightweight live display; final assessments use SwiftF0 in Core.
                guard gate.wait(timeout: .now()) == .success else { return }
                queue.async {
                    defer { gate.signal() }
                    let pitch = LiveDSP.pitch(pcm, rate: rate)
                    let bins = LiveDSP.spectrum(pcm)
                    Task { @MainActor in
                        guard let self, self.recording else { return }
                        self.pitches.append(pitch)
                        if self.pitches.count > 160 { self.pitches.removeFirst() }
                        self.spectrum = bins
                    }
                }
            }
            try capture.start(); recording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.seconds += 0.1
                    if let self, self.seconds >= 120 { self.cancel(); self.error = "单次录音上限为 120 秒，请重新录制较短片段。" }
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    func cancel() { timer?.invalidate(); timer = nil; capture.cancel(); recording = false }

    func resetResult() { latest = nil }

    func finish(history: HistoryStore, masculine: Bool, healthOnly: Bool = false, retain: Bool) {
        guard recording else { return }
        timer?.invalidate(); timer = nil; recording = false
        do {
            let audio = try capture.stop()
            guard Double(audio.samples.count) / audio.rate >= 5 else {
                try? FileManager.default.removeItem(at: audio.file)
                error = "请至少录制 5 秒。"; return
            }
            busy = true
            worker.async { [weak self] in
                do {
                    guard let directory = Bundle.main.url(forResource: "models", withExtension: nil) else { throw AnalysisError.models }
                    let analyzer = try PitcheeAnalyzer(modelDirectory: directory)
                    let json: String
                    if healthOnly { json = try analyzer.voiceHealth(samples: audio.samples, rate: Int32(audio.rate)) }
                    else { json = try analyzer.analyze(samples: audio.samples, sampleRate: Int32(audio.rate), channels: 1, scoreProfile: masculine ? PITCHEE_SCORE_PROFILE_MASCULINIZATION : PITCHEE_SCORE_PROFILE_FEMINIZATION) }
                    Task { @MainActor in
                        guard let self else { return }
                        defer { self.busy = false }
                        do {
                            if healthOnly { self.health = Double(json) }
                            else {
                                _ = try JSONDecoder().decode(AnalysisResult.self, from: Data(json.utf8))
                                let assessment = Assessment(profile: masculine ? "masculinization" : "feminization", json: json, audioFile: retain ? audio.file.lastPathComponent : nil)
                                try history.add(assessment)
                                self.latest = assessment
                            }
                            if !retain || healthOnly { try? FileManager.default.removeItem(at: audio.file) }
                        } catch { self.error = error.localizedDescription; try? FileManager.default.removeItem(at: audio.file) }
                    }
                } catch {
                    try? FileManager.default.removeItem(at: audio.file)
                    Task { @MainActor in self?.busy = false; self?.error = error.localizedDescription }
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    enum AnalysisError: LocalizedError {
        case models
        var errorDescription: String? { "应用内缺少模型文件，请检查构建资源。" }
    }
}

enum LiveDSP {
    static func pitch(_ pcm: [Float], rate: Double) -> Double {
        guard pcm.count > 512 else { return 0 }
        let energy = pcm.reduce(0.0) { $0 + Double($1 * $1) }
        guard energy / Double(pcm.count) > 0.00001 else { return 0 }
        let low = Int(rate / 600), high = min(Int(rate / 75), pcm.count / 2)
        guard high > low else { return 0 }
        var best = 0.0, lag = 0
        for shift in low...high {
            var cross = 0.0, left = 0.0, right = 0.0
            for i in stride(from: 0, to: pcm.count - high, by: 3) {
                let a = Double(pcm[i]), b = Double(pcm[i + shift])
                cross += a * b; left += a * a; right += b * b
            }
            let corr = cross / max(sqrt(left * right), 1e-12)
            if corr > best { best = corr; lag = shift }
        }
        return best > 0.75 && lag > 0 ? rate / Double(lag) : 0
    }
    static func spectrum(_ pcm: [Float]) -> [Float] {
        let n = min(512, pcm.count)
        guard n > 0 else { return [] }
        return (1...64).map { k in
            var re = 0.0, im = 0.0
            for i in 0..<n {
                let angle = 2 * Double.pi * Double(k * i) / Double(n)
                let window = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n))
                re += Double(pcm[i]) * window * cos(angle)
                im -= Double(pcm[i]) * window * sin(angle)
            }
            return Float(max(-80, 20 * log10(max(sqrt(re * re + im * im) / Double(n), 1e-8))))
        }
    }
}
