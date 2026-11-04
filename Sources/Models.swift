import Foundation
import Combine

struct Assessment: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    let profile: String
    let json: String
    let audioFile: String?
    var result: AnalysisResult? { try? JSONDecoder().decode(AnalysisResult.self, from: Data(json.utf8)) }
}

struct AnalysisResult: Decodable {
    struct F0: Decodable { let mean_hz: Double? }
    struct VFP: Decodable { let vfp_standard_score: Double }
    struct Naturalness: Decodable { let score: Double }
    struct Composite: Decodable { let final_score: Double; let rule: String }
    let f0: F0
    let vfp: VFP
    let naturalness: Naturalness
    let composite: Composite
}

@MainActor final class HistoryStore: ObservableObject {
    @Published private(set) var items: [Assessment] = []
    @Published var error: String?
    nonisolated static var directory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var file: URL { Self.directory.appendingPathComponent("history.json") }
    init() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { items = try JSONDecoder().decode([Assessment].self, from: Data(contentsOf: file)) }
        catch { self.error = "历史记录读取失败：\(error.localizedDescription)" }
    }
    func add(_ item: Assessment) throws {
        let updated = [item] + items
        try JSONEncoder().encode(updated).write(to: file, options: .atomic)
        items = updated
    }
    func delete(at offsets: IndexSet) {
        let removed = offsets.map { items[$0] }
        let updated = items.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        do {
            try JSONEncoder().encode(updated).write(to: file, options: .atomic)
            items = updated
            for item in removed {
                if let audio = item.audioFile { try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(audio)) }
            }
        } catch { self.error = error.localizedDescription }
    }
}
