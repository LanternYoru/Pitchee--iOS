import AVFoundation
import Foundation

struct PCMRecording {
    let samples: [Float]
    let rate: Double
    let file: URL
}

// All tap data is copied before leaving the audio callback. A lock protects
// recording storage; UI work and inference never run on the audio thread.
final class AudioCapture {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var rate: Double = 0
    private var active = false
    var onFrame: (([Float], Double) -> Void)?

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.unavailable }
        lock.lock(); samples = []; rate = format.sampleRate; active = true; lock.unlock()
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let channels = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength)
            var mono = [Float](repeating: 0, count: count)
            for c in 0..<Int(buffer.format.channelCount) {
                for i in 0..<count { mono[i] += channels[c][i] / Float(buffer.format.channelCount) }
            }
            self.lock.lock()
            if self.active { self.samples.append(contentsOf: mono) }
            self.lock.unlock()
            self.onFrame?(mono, format.sampleRate)
        }
        do { try engine.start() }
        catch { cancel(); throw error }
    }
    func stop() throws -> PCMRecording {
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        lock.lock(); active = false; let pcm = samples; let sr = rate; samples = []; lock.unlock()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let url = HistoryStore.directory.appendingPathComponent(UUID().uuidString + ".wav")
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count)) else { throw CaptureError.unavailable }
        buffer.frameLength = AVAudioFrameCount(pcm.count)
        pcm.withUnsafeBufferPointer { ptr in
            if let source = ptr.baseAddress { buffer.floatChannelData![0].update(from: source, count: pcm.count) }
        }
        try RecordingAudio.writeWAV(buffer, to: url)
        return PCMRecording(samples: pcm, rate: sr, file: url)
    }
    func cancel() {
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        lock.lock(); active = false; samples = []; lock.unlock()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    enum CaptureError: LocalizedError {
        case unavailable
        var errorDescription: String? { "无法访问音频输入，请检查麦克风或耳机。" }
    }
}
