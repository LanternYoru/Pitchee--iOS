import AVFoundation
import Combine
import Foundation

enum RecordingAudio {
    static func writeWAV(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: buffer.format.sampleRate,
                                         channels: buffer.format.channelCount,
                                         interleaved: true) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                       commonFormat: buffer.format.commonFormat,
                                       interleaved: buffer.format.isInterleaved)
            try file.write(from: buffer)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    static func makePlayer(for url: URL) throws -> AVAudioPlayer {
        guard url.pathExtension.lowercased() == "caf" else {
            return try AVAudioPlayer(contentsOf: url)
        }
        // Earlier versions saved floating-point PCM in CAF. Decode it with
        // AVAudioFile and give the playback engine a standard 16-bit WAV.
        let source = try AVAudioFile(forReading: url)
        guard source.length > 0, source.length <= Int64(UInt32.max),
              let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat,
                                            frameCapacity: AVAudioFrameCount(source.length)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try source.read(into: buffer)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try writeWAV(buffer, to: temporary)
        return try AVAudioPlayer(data: Data(contentsOf: temporary))
    }
}

@MainActor final class RecordingPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published var error: String?
    private var player: AVAudioPlayer?
    private var sessionActive = false

    func toggle(_ audioFile: String) {
        if isPlaying {
            stop()
            return
        }
        do {
            let next = try RecordingAudio.makePlayer(for: HistoryStore.directory.appendingPathComponent(audioFile))
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            sessionActive = true
            player = next
            next.delegate = self
            guard next.prepareToPlay(), next.play() else {
                stop()
                error = "音频无法播放。请尝试重新录音。"
                return
            }
            isPlaying = true
        } catch {
            stop()
            self.error = error.localizedDescription
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.stop()
            if !flag { self.error = "录音播放中断。" }
        }
    }
}
