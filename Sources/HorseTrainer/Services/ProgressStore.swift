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
    // Gym / gamification
    var xp = 0
    var activeDays: [String] = []
    var workoutsCompleted = 0
    var bestCombo = 0
    var repsToday = 0
    var repsDay = ""
    /// Last 20 results per skill key (drill concept raw value, "value", "inout", ...) for adaptive workouts.
    var recent: [String: [Bool]] = [:]

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
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        activeDays = try c.decodeIfPresent([String].self, forKey: .activeDays) ?? []
        workoutsCompleted = try c.decodeIfPresent(Int.self, forKey: .workoutsCompleted) ?? 0
        bestCombo = try c.decodeIfPresent(Int.self, forKey: .bestCombo) ?? 0
        repsToday = try c.decodeIfPresent(Int.self, forKey: .repsToday) ?? 0
        repsDay = try c.decodeIfPresent(String.self, forKey: .repsDay) ?? ""
        recent = try c.decodeIfPresent([String: [Bool]].self, forKey: .recent) ?? [:]
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
        rep(concept.rawValue, correct: correct)
        save()
    }

    // MARK: - Gym

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static var today: String { dayFormatter.string(from: Date()) }

    /// One training rep: XP, skill history, daily rep count (20 reps = an active day).
    func rep(_ skill: String, correct: Bool, xp: Int? = nil) {
        var h = progress.recent[skill] ?? []
        h.append(correct)
        progress.recent[skill] = Array(h.suffix(20))
        progress.xp += xp ?? (correct ? 10 : 2)
        if progress.repsDay != Self.today {
            progress.repsDay = Self.today
            progress.repsToday = 0
        }
        progress.repsToday += 1
        if progress.repsToday >= 20 { markActiveToday() }
    }

    func addXP(_ n: Int) {
        progress.xp += n
        save()
    }

    func markActiveToday() {
        if !progress.activeDays.contains(Self.today) { progress.activeDays.append(Self.today) }
    }

    func completeWorkout(bestCombo: Int) {
        progress.workoutsCompleted += 1
        progress.bestCombo = max(progress.bestCombo, bestCombo)
        progress.xp += 50
        markActiveToday()
        save()
    }

    var repsToday: Int { progress.repsDay == Self.today ? progress.repsToday : 0 }
    var activeToday: Bool { progress.activeDays.contains(Self.today) }

    /// Consecutive active days ending today (or yesterday, if today isn't done yet).
    var streak: Int {
        let days = Set(progress.activeDays)
        let cal = Calendar.current
        var d = Date()
        if !days.contains(Self.dayFormatter.string(from: d)) { d = cal.date(byAdding: .day, value: -1, to: d)! }
        var n = 0
        while days.contains(Self.dayFormatter.string(from: d)) {
            n += 1
            d = cal.date(byAdding: .day, value: -1, to: d)!
        }
        return n
    }

    /// Accuracy over the last 20 reps of a skill (nil if fewer than 3).
    func skillRate(_ key: String) -> Double? {
        guard let h = progress.recent[key], h.count >= 3 else { return nil }
        return Double(h.filter { $0 }.count) / Double(h.count)
    }

    static let levelTitles = ["Tourist", "Rec", "Regular", "Grinder", "Reg", "Shark", "Crusher", "Pro"]

    var level: Int { Int((Double(progress.xp) / 100).squareRoot()) + 1 }
    func xpFor(level l: Int) -> Int { (l - 1) * (l - 1) * 100 }
    var levelTitle: String { Self.levelTitles[min(level - 1, Self.levelTitles.count - 1)] }
    var levelProgress: Double {
        let lo = xpFor(level: level), hi = xpFor(level: level + 1)
        return Double(progress.xp - lo) / Double(max(1, hi - lo))
    }

    func recordInverse(_ type: PlayerType, correct: Bool) {
        progress.inverseByType[type.rawValue, default: Tally()].add(correct)
        rep("readbet", correct: correct)
        save()
    }

    func recordValue(_ type: PlayerType, correct: Bool) {
        progress.valueByType[type.rawValue, default: Tally()].add(correct)
        rep("value", correct: correct)
        save()
    }

    func recordRangeQuiz(_ kind: String, correct: Bool) {
        progress.rangeQuiz[kind, default: Tally()].add(correct)
        rep("range-" + kind, correct: correct)
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
        rep("sizeit", correct: correct)
        save()
    }

    func recordQuiz(_ q: QuizRecord, perType: [(PlayerType, Bool)]) {
        progress.quizzes.append(q)
        progress.xp += q.correct * 15
        for (t, ok) in perType { progress.classifyByType[t.rawValue, default: Tally()].add(ok) }
        save()
    }

    func recordSession(_ s: SessionRecord) {
        guard s.hands > 0 else { return }
        progress.sessions.append(s)
        progress.xp += s.hands + s.good * 5
        if s.hands >= 30 { markActiveToday() }
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
