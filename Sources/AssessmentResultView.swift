import SwiftUI

struct AssessmentResultView: View {
    @EnvironmentObject private var history: HistoryStore
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var playback = RecordingPlayback()
    @State private var comparing = false
    let item: Assessment
    var showsDate = false

    private var previous: AnalysisResult? {
        history.items.first { $0.date < item.date && $0.profile == item.profile }?.result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsDate {
                Text(item.date, format: .dateTime.year().month().day().hour().minute())
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let result = item.result {
                scoreCircles(result.composite.final_score)
                if let audio = item.audioFile {
                    Button { playback.toggle(audio) } label: {
                        Image(systemName: playback.isPlaying ? "stop.fill" : "play.fill")
                            .font(.headline)
                            .frame(width: 48, height: 48)
                            .foregroundStyle(Color(red: 0.05, green: 0.15, blue: 0.29))
                            .background(Color(red: 0.52, green: 0.72, blue: 0.98), in: Circle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(playback.isPlaying ? "停止播放" : "播放录音")
                }
                metrics(comparing ? previous ?? result : result)
                suggestion(result)
            }
            ShareLink("导出分析 JSON", item: item.json)
        }
        .onDisappear { playback.stop() }
        .alert("播放失败", isPresented: Binding(get: { playback.error != nil }, set: { if !$0 { playback.error = nil } })) {
            Button("好") { playback.error = nil }
        } message: { Text(playback.error ?? "") }
    }

    private func scoreCircles(_ score: Double) -> some View {
        let target = min(100, max(0, score))
        let pink = item.profile == "masculinization" ? 100 - target : target
        let blue = 100 - pink
        return GeometryReader { proxy in
            let scale = min(proxy.size.width / 300, 1)
            ZStack {
                scoreCircle(blue, color: Color(red: 0.38, green: 0.59, blue: 0.90),
                            ink: Color(red: 0.04, green: 0.14, blue: 0.29), scale: scale)
                    .offset(x: -43 * scale, y: 39 * scale)
                scoreCircle(pink, color: Color(red: 1, green: 0.71, blue: 0.76),
                            ink: Color(red: 0.26, green: 0.08, blue: 0.13), scale: scale)
                    .offset(x: 43 * scale, y: -39 * scale)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(height: 280)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("女性化 \(String(format: "%.1f", pink))%，男性化 \(String(format: "%.1f", blue))%")
    }

    private func scoreCircle(_ score: Double, color: Color, ink: Color, scale: Double) -> some View {
        let size = (76 + score * 1.76) * scale
        return Text(String(format: "%.1f%%", score))
            .font(.system(size: size * 0.225, weight: .black, design: .rounded))
            .monospacedDigit().foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(color, in: Circle())
    }

    private func metrics(_ result: AnalysisResult) -> some View {
        let pitch = result.f0.mean_hz
        let masculine = item.profile == "masculinization"
        let pitchScore = pitch.map { masculine ? (250 - $0) / 1.5 : ($0 - 100) / 1.2 } ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(comparing ? "上次指标" : "我的指标").font(.title3.bold())
                Spacer()
                if previous != nil {
                    Button(comparing ? "返回本次" : "对比上次") { comparing.toggle() }
                        .buttonStyle(.bordered).clipShape(Capsule())
                }
            }
            Divider()
            metric("音色分 S", score: result.vfp.vfp_standard_score)
            metric("自然度 N", score: result.naturalness.score)
            metric("平均音高 F0", score: pitchScore, value: pitch.map { String(format: "%.0f Hz", $0) } ?? "未检测到")
            Text("＊按 100–250 Hz 映射").font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(cardColor, in: RoundedRectangle(cornerRadius: 20))
    }

    private func metric(_ title: String, score: Double, value: String? = nil) -> some View {
        let tint: Color = score >= 60 ? .green : score >= 40 ? .yellow : .orange
        return VStack(spacing: 6) {
            HStack {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(title)
                Spacer()
                Text(value ?? String(format: "%.1f", score)).monospacedDigit()
            }
            ProgressView(value: min(100, max(0, score)), total: 100).tint(tint)
                .accessibilityHidden(true)
        }
    }

    private func suggestion(_ result: AnalysisResult) -> some View {
        let article = suggestionArticle(result)
        return VStack(alignment: .leading, spacing: 12) {
            Text("建议").font(.title3.bold())
            NavigationLink {
                if let article {
                    ScrollView {
                        Text(article).frame(maxWidth: .infinity, alignment: .leading).padding()
                    }.navigationTitle("训练建议")
                } else {
                    KnowledgeView()
                }
            } label: {
                HStack {
                    Image(systemName: "text.book.closed.fill").foregroundStyle(.orange)
                    Text(article?.split(separator: "\n").first(where: { $0.hasPrefix("# ") })
                        .map { String($0.dropFirst(2)) } ?? "查看训练知识库")
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 20))
    }

    private var cardColor: Color {
        colorScheme == .dark ? Color(red: 0.16, green: 0.11, blue: 0.09) : Color.orange.opacity(0.08)
    }

    private func suggestionArticle(_ result: AnalysisResult) -> String? {
        guard item.profile != "masculinization" else { return nil }
        let name: String
        switch result.composite.rule {
        case "continuous": name = result.composite.final_score >= 60 ? "02-feminization-continuous-pass" : "01-feminization-continuous-nopass"
        case "pass_boost": name = "03-pass-boost"
        case "high_f0_stylized_cap": name = "04-high-f0-stylized-cap"
        case "low_f0_natural_cap": name = "05-low-f0-natural-cap"
        case "low_f0_stylized_cap": name = "06-low-f0-stylized-cap"
        case "high_f0_male_cap": name = "07-high-f0-male-cap"
        default: return nil
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "Knowledge/rules") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
