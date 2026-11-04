import SwiftUI
import Charts
import AVFoundation

@main struct PitcheeApp: App {
    @StateObject private var history = HistoryStore()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(history).tint(.orange) }
    }
}

struct RootView: View {
    @EnvironmentObject private var history: HistoryStore
    var body: some View {
        TabView {
            NavigationStack { CaptureView() }.tabItem { Label("分析", systemImage: "waveform") }
            NavigationStack { DashboardView() }.tabItem { Label("记录", systemImage: "chart.xyaxis.line") }
            NavigationStack { ToolsView() }.tabItem { Label("工具", systemImage: "pianokeys") }
            NavigationStack { SettingsView() }.tabItem { Label("设置", systemImage: "gearshape") }
        }
        .alert("存储错误", isPresented: Binding(get: { history.error != nil }, set: { if !$0 { history.error = nil } })) {
            Button("好") { history.error = nil }
        } message: { Text(history.error ?? "") }
    }
}

struct CaptureView: View {
    @EnvironmentObject private var history: HistoryStore
    @StateObject private var voice = VoiceModel()
    @AppStorage("masculine") private var masculine = false
    @AppStorage("retainAudio") private var retain = true
    @Environment(\.scenePhase) private var scenePhase
    var healthOnly = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let item = voice.latest {
                    AssessmentResultView(item: item)
                    Button("重新录音") { voice.resetResult() }
                        .frame(maxWidth: .infinity)
                } else {
                    Text(healthOnly ? "关注声音的状态" : "听见自己的变化").font(.largeTitle.bold())
                    Text("在安静环境中自然朗读至少 5 秒。声音只在本机处理。")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ReadingPassage.title).font(.headline)
                        Text(ReadingPassage.text).font(.body)
                    }.padding().background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                    if voice.recording {
                        Text(voice.seconds, format: .number.precision(.fractionLength(1))).font(.system(size: 48, weight: .light, design: .rounded))
                        PitchPlot(values: voice.pitches)
                    }
                    if voice.busy { ProgressView("正在本地分析，请稍候…").padding() }
                    Button {
                        if voice.recording { voice.finish(history: history, masculine: masculine, healthOnly: healthOnly, retain: retain) }
                        else { Task { await voice.start() } }
                    } label: {
                        Label(voice.recording ? "结束并分析" : "开始录音", systemImage: voice.recording ? "stop.fill" : "mic.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.buttonStyle(.borderedProminent).disabled(voice.busy)
                    if let health = voice.health {
                        LabeledContent("声音健康评分", value: health.formatted(.number.precision(.fractionLength(1))))
                        Text("这是模型评估结果，不能用于诊断。若持续不适，请停止练习并咨询专业人士。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }.padding()
        }.navigationTitle(healthOnly ? "声音健康" : voice.latest == nil ? "声音分析" : "分析结果")
        .alert("无法完成", isPresented: Binding(get: { voice.error != nil }, set: { if !$0 { voice.error = nil } })) {
            Button("好") { voice.error = nil }
        } message: { Text(voice.error ?? "") }
        .onDisappear { if voice.recording { voice.cancel() } }
        .onChange(of: scenePhase) { if $0 != .active && voice.recording { voice.cancel() } }
    }
}

struct PitchPlot: View {
    let values: [Double]
    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            if item.element > 0 { PointMark(x: .value("时间", item.offset), y: .value("Hz", item.element)).foregroundStyle(.orange) }
        }.chartYScale(domain: 50...650).frame(height: 180)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var history: HistoryStore
    @State private var selectedDate = Date()
    @State private var filterDate = false
    private var visible: [Assessment] {
        history.items.filter { !filterDate || Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }
    var body: some View {
        List {
            Section("成长趋势 · \(history.items.count) 次分析") {
                Chart(history.items.reversed()) { item in
                    if let result = item.result {
                        LineMark(x: .value("日期", item.date), y: .value("评分", result.composite.final_score))
                            .foregroundStyle(by: .value("训练方向", item.profile))
                    }
                }.chartYScale(domain: 0...100).frame(height: 180)
            }
            Section {
                Toggle("按日期查看", isOn: $filterDate)
                if filterDate { DatePicker("日期", selection: $selectedDate, displayedComponents: .date).datePickerStyle(.graphical) }
            }
            Section("历史记录") {
                if visible.isEmpty { Text("还没有记录，开始一次录音吧。").foregroundStyle(.secondary) }
                ForEach(visible) { item in
                    NavigationLink {
                        AssessmentDetail(item: item)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.date, style: .date)
                                Text(item.profile == "masculinization" ? "男性化训练" : "女性化训练").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.result?.composite.final_score.formatted(.number.precision(.fractionLength(1))) ?? "—")
                        }
                    }
                }.onDelete { offsets in
                    let ids = Set(offsets.map { visible[$0].id })
                    history.delete(at: IndexSet(history.items.indices.filter { ids.contains(history.items[$0].id) }))
                }
            }
        }.navigationTitle("我的记录")
    }
}

struct AssessmentDetail: View {
    let item: Assessment
    var body: some View {
        ScrollView {
            AssessmentResultView(item: item, showsDate: true).padding()
        }.navigationTitle("分析结果")
    }
}

struct ToolsView: View {
    var body: some View {
        List {
            NavigationLink("实时音高与频谱", destination: LiveView())
            NavigationLink("声音健康", destination: CaptureView(healthOnly: true))
            NavigationLink("钢琴", destination: PianoView())
            NavigationLink("知识库", destination: KnowledgeView())
        }.navigationTitle("练习工具")
    }
}

struct LiveView: View {
    @StateObject private var voice = VoiceModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(voice.pitches.last.flatMap { $0 > 0 ? String(format: "%.0f Hz", $0) : nil } ?? "— Hz").font(.largeTitle.monospacedDigit())
                PitchPlot(values: voice.pitches)
                Text("实时频谱 · 频率由左向右递增").font(.caption).foregroundStyle(.secondary)
                Chart(Array(voice.spectrum.enumerated()), id: \.offset) { item in
                    BarMark(x: .value("频率分箱", item.offset), yStart: .value("下限", -80), yEnd: .value("dBFS", item.element))
                }.chartYScale(domain: Float(-80)...Float(0)).frame(height: 180)
                Button(voice.recording ? "停止" : "开始监听") { if voice.recording { voice.cancel() } else { Task { await voice.start() } } }.buttonStyle(.borderedProminent)
                Text("实时音高为自相关估计；正式分析使用原项目 SwiftF0 模型。监听最长 120 秒，不保存音频。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("实时声音")
        .onDisappear { voice.cancel() }
        .onChange(of: scenePhase) { if $0 != .active { voice.cancel() } }
        .alert("音频错误", isPresented: Binding(get: { voice.error != nil }, set: { if !$0 { voice.error = nil } })) { Button("好") { voice.error = nil } } message: { Text(voice.error ?? "") }
    }
}

struct SettingsView: View {
    @AppStorage("masculine") private var masculine = false
    @AppStorage("retainAudio") private var retain = true
    var body: some View {
        Form {
            Section("训练偏好") { Toggle("男性化评分（关闭为女性化）", isOn: $masculine); Toggle("保留分析录音", isOn: $retain) }
            Section("隐私") { Text("录音、推理与历史记录均保存在设备上。删除记录时会同时删除对应录音。关闭保留录音只影响后续分析。") }
            Section("开源许可") {
                Text("Pitchee iOS · GPL-3.0-only\n基于 Project-Pitchee/Pitchee-Android 与 PitcheeCore。ncnn 使用 BSD-3-Clause；模型许可见源码 Vendor/PitcheeCore/models。")
                Link("上游项目", destination: URL(string: "https://github.com/Project-Pitchee/Pitchee-Android")!)
                NavigationLink("许可全文") {
                    List(["GPL-3.0", "ncnn"], id: \.self) { name in
                        NavigationLink(name) {
                            ScrollView {
                                Text(Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Licenses").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "无法读取许可")
                                    .font(.footnote).textSelection(.enabled).padding()
                            }.navigationTitle(name)
                        }
                    }.navigationTitle("开源许可")
                }
            }
        }.navigationTitle("设置")
    }
}
