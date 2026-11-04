import SwiftUI
import AVFoundation

final class PianoPlayer: ObservableObject {
    private var player: AVAudioPlayer?
    func play(midi: Int) throws {
        let rate = 44100.0
        let frequency = 440 * pow(2, Double(midi - 69) / 12)
        let count = Int(rate * 0.8)
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); word(UInt32(36 + count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8); word(UInt32(16)); word(UInt16(1)); word(UInt16(1))
        word(UInt32(rate)); word(UInt32(rate * 2)); word(UInt16(2)); word(UInt16(16))
        data.append(contentsOf: "data".utf8); word(UInt32(count * 2))
        for i in 0..<count {
            let time = Double(i) / rate
            let envelope = min(1, time * 100) * exp(-5 * time)
            let signal = sin(2 * .pi * frequency * time) + 0.25 * sin(4 * .pi * frequency * time)
            word(Int16(signal * envelope * 15000))
        }
        try AVAudioSession.sharedInstance().setCategory(.playback)
        try AVAudioSession.sharedInstance().setActive(true)
        player = try AVAudioPlayer(data: data); player?.play()
    }
    func stop() { player?.stop(); try? AVAudioSession.sharedInstance().setActive(false) }
}

struct PianoView: View {
    @StateObject private var piano = PianoPlayer()
    @State private var selected: Int?
    @State private var error: String?
    let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(selected.map { String(format: "%.1f Hz", 440 * pow(2, Double($0 - 69) / 12)) } ?? "选择音符，轻松跟唱").font(.title2)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(48...84, id: \.self) { midi in
                        Button {
                            do { try piano.play(midi: midi); selected = midi } catch { self.error = error.localizedDescription }
                        } label: {
                            Text("\(names[midi % 12])\(midi / 12 - 1)")
                                .frame(maxWidth: .infinity, minHeight: 65)
                                .background(names[midi % 12].contains("♯") ? Color.primary.opacity(0.15) : Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }.padding()
        }.navigationTitle("钢琴 · C3–C6").onDisappear { piano.stop() }
        .alert("播放失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
    }
}

struct KnowledgeView: View {
    private var articles: [URL] {
        guard let root = Bundle.main.url(forResource: "Knowledge", withExtension: nil),
              let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "md" && !$0.path.contains("/en/") }.sorted { $0.path < $1.path }
    }
    private func title(_ url: URL) -> String {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text.components(separatedBy: .newlines).first(where: { $0.hasPrefix("# ") }).map { String($0.dropFirst(2)) } ?? url.deletingPathExtension().lastPathComponent
    }
    var body: some View {
        List(articles, id: \.self) { url in
            NavigationLink(title(url)) {
                ScrollView {
                    // Display source text faithfully, including equations that
                    // SwiftUI's inline Markdown renderer cannot typeset.
                    Text((try? String(contentsOf: url, encoding: .utf8)) ?? "文章读取失败")
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                }.navigationTitle(title(url)).navigationBarTitleDisplayMode(.inline)
            }
        }.navigationTitle("知识库")
    }
}
