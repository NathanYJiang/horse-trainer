import Foundation
import PokerCore

struct Tally: Codable, Equatable {
    var attempts = 0
    var correct = 0
    var rate: Double { attempts == 0 ? 0 : Double(correct) / Double(attempts) }
}

struct QuizRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var handsObserved: Int
    var correct: Int
    var total: Int
}

struct SessionRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var preset: String
    var hands: Int
    var net: Int
    var good: Int
    var inaccuracies: Int
    var mistakes: Int
}

struct Progress: Codable, Equatable {
    var drillByConcept: [String: Tally] = [:]
    var drillByType: [String: Tally] = [:]
    var inverseByType: [String: Tally] = [:]
    var valueByType: [String: Tally] = [:]
    var sizeItByType: [String: Tally] = [:]
    var quizzes: [QuizRecord] = []
    var sessions: [SessionRecord] = []
    var classifyByType: [String: Tally] = [:]
    var rangeQuiz: [String: Tally] = [:]
    var savedRanges: [String: String] = [:]

    init() {}

    // Tolerant decoding so older progress files keep working as fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        drillByConcept = try c.decodeIfPresent([String: Tally].self, forKey: .drillByConcept) ?? [:]
        drillByType = try c.decodeIfPresent([String: Tally].self, forKey: .drillByType) ?? [:]
        inverseByType = try c.decodeIfPresent([String: Tally].self, forKey: .inverseByType) ?? [:]
        valueByType = try c.decodeIfPresent([String: Tally].self, forKey: .valueByType) ?? [:]
        sizeItByType = try c.decodeIfPresent([String: Tally].self, forKey: .sizeItByType) ?? [:]
        quizzes = try c.decodeIfPresent([QuizRecord].self, forKey: .quizzes) ?? []
        sessions = try c.decodeIfPresent([SessionRecord].self, forKey: .sessions) ?? []
        classifyByType = try c.decodeIfPresent([String: Tally].self, forKey: .classifyByType) ?? [:]
        rangeQuiz = try c.decodeIfPresent([String: Tally].self, forKey: .rangeQuiz) ?? [:]
        savedRanges = try c.decodeIfPresent([String: String].self, forKey: .savedRanges) ?? [:]
    }
}

@MainActor
@Observable
final class ProgressStore {
    var progress = Progress()

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HorseTrainer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("progress.json")
    }

    init() {
        if let data = try? Data(contentsOf: url), let p = try? JSONDecoder().decode(Progress.self, from: data) {
            progress = p
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(progress) { try? data.write(to: url, options: .atomic) }
    }

    func recordDrill(_ concept: DrillConcept, _ type: PlayerType, correct: Bool) {
        progress.drillByConcept[concept.rawValue, default: Tally()].add(correct)
        progress.drillByType[type.rawValue, default: Tally()].add(correct)
        save()
    }

    func recordInverse(_ type: PlayerType, correct: Bool) {
        progress.inverseByType[type.rawValue, default: Tally()].add(correct)
        save()
    }

    func recordValue(_ type: PlayerType, correct: Bool) {
        progress.valueByType[type.rawValue, default: Tally()].add(correct)
        save()
    }

    func recordRangeQuiz(_ kind: String, correct: Bool) {
        progress.rangeQuiz[kind, default: Tally()].add(correct)
        save()
    }

    func saveRange(_ name: String, _ notation: String) {
        progress.savedRanges[name] = notation
        save()
    }

    func deleteRange(_ name: String) {
        progress.savedRanges[name] = nil
        save()
    }

    func recordSizeIt(_ type: PlayerType, correct: Bool) {
        progress.sizeItByType[type.rawValue, default: Tally()].add(correct)
        save()
    }

    func recordQuiz(_ q: QuizRecord, perType: [(PlayerType, Bool)]) {
        progress.quizzes.append(q)
        for (t, ok) in perType { progress.classifyByType[t.rawValue, default: Tally()].add(ok) }
        save()
    }

    func recordSession(_ s: SessionRecord) {
        guard s.hands > 0 else { return }
        progress.sessions.append(s)
        save()
    }

    func reset() {
        let saved = progress.savedRanges
        progress = Progress()
        progress.savedRanges = saved
        save()
    }
}

extension Tally {
    mutating func add(_ ok: Bool) {
        attempts += 1
        if ok { correct += 1 }
    }
}
