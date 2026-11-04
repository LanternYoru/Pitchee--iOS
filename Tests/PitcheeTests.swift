import XCTest
import AVFoundation
import CPitcheeCore
@testable import Pitchee

final class PitcheeTests: XCTestCase {
    func testPlaybackOpensNewWAVAndLegacyCAF() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
        buffer.frameLength = 1600
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for i in 0..<1600 { samples[i] = 0.25 * sin(Float(i) * 0.1) }

        let wav = directory.appendingPathComponent("current.wav")
        try RecordingAudio.writeWAV(buffer, to: wav)
        let caf = directory.appendingPathComponent("legacy.caf")
        do {
            let file = try AVAudioFile(forWriting: caf, settings: format.settings)
            try file.write(from: buffer)
        }
        for url in [wav, caf] {
            let player = try RecordingAudio.makePlayer(for: url)
            XCTAssertEqual(player.duration, 0.1, accuracy: 0.001)
            XCTAssertEqual(player.numberOfChannels, 1)
        }
    }

    func testBundledModelsAnalyzeRealSpeech() throws {
        let models = try XCTUnwrap(Bundle.main.url(forResource: "models", withExtension: nil))
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "speech", withExtension: "m4a"))
        let file = try AVAudioFile(forReading: fixture)
        let format = file.processingFormat
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let analyzer = try PitcheeAnalyzer(modelDirectory: models)
        let raw = try analyzer.analyze(samples: samples, sampleRate: Int32(format.sampleRate), channels: 1, scoreProfile: PITCHEE_SCORE_PROFILE_FEMINIZATION)
        let result = try JSONDecoder().decode(AnalysisResult.self, from: Data(raw.utf8))
        XCTAssertTrue((0...100).contains(result.composite.final_score))
        XCTAssertTrue((0...100).contains(result.vfp.vfp_standard_score))
        XCTAssertGreaterThan(try XCTUnwrap(result.f0.mean_hz), 50)
    }
    func testLivePitchDetectsSineAndSilence() {
        let sine = (0..<4096).map { Float(sin(2 * Double.pi * 220 * Double($0) / 48000)) * 0.5 }
        XCTAssertEqual(LiveDSP.pitch(sine, rate: 48000), 220, accuracy: 3)
        XCTAssertEqual(LiveDSP.pitch([Float](repeating: 0, count: 4096), rate: 48000), 0)
    }
}
