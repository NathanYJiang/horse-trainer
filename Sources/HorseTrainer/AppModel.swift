import Foundation
import PokerCore
import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case home, workout, live, reads, drills, sizing, ranges, equity, playbook, progress, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .workout: "Daily Workout"
        case .live: "Live Table"
        case .reads: "Read the Table"
        case .drills: "Exploit Drills"
        case .sizing: "Sizing Lab"
        case .ranges: "Range Builder"
        case .equity: "Equity Calculator"
        case .playbook: "Playbook"
        case .progress: "Progress"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .workout: "flame"
        case .live: "suit.spade"
        case .reads: "eye"
        case .drills: "target"
        case .sizing: "slider.horizontal.3"
        case .ranges: "square.grid.3x3"
        case .equity: "percent"
        case .playbook: "book"
        case .progress: "chart.bar"
        case .settings: "gearshape"
        }
    }

    /// One-line description shown in the sidebar tooltip and on Home.
    var blurb: String {
        switch self {
        case .home: "Your dashboard and what to do next"
        case .workout: "15 fresh reps a day, 3 rounds"
        case .live: "Play a 1/2 table vs realistic player types"
        case .reads: "Watch hands and classify every seat"
        case .drills: "Same spot, different villain, different answer"
        case .sizing: "Bet the most they'll call, and read their bets"
        case .ranges: "Learn what top 10/15/20% looks like"
        case .equity: "Hand vs hand or range equity"
        case .playbook: "Player types and principles"
        case .progress: "Accuracy, sessions and streaks"
        case .settings: "Speed, deck, Claude key"
        }
    }

    var shortcut: KeyEquivalent? {
        switch self {
        case .home: "1"
        case .workout: "2"
        case .live: "3"
        case .reads: "4"
        case .drills: "5"
        case .sizing: "6"
        case .ranges: "7"
        case .equity: "8"
        case .playbook: "9"
        default: nil
        }
    }
}

enum Modal: Identifiable {
    case newTable(GameController)
    case quiz(GameController)
    case sessionReport(GameController, startNewAfter: Bool)

    var id: String {
        switch self {
        case .newTable: "new"
        case .quiz: "quiz"
        case .sessionReport: "report"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    private let d = UserDefaults.standard

    var apiKey: String { didSet { KeyStore.write(apiKey) } }
    var model: String { didSet { d.set(model, forKey: "model") } }
    var effort: String { didSet { d.set(effort, forKey: "effort") } }
    var botSpeed: Double { didSet { d.set(botSpeed, forKey: "botSpeed") } }
    var fourColor: Bool { didSet { d.set(fourColor, forKey: "fourColor") } }
    var instantFeedback: Bool { didSet { d.set(instantFeedback, forKey: "instantFeedback") } }
    var autoDeal: Bool { didSet { d.set(autoDeal, forKey: "autoDeal") } }
    var heroStraddles: Bool { didSet { d.set(heroStraddles, forKey: "heroStraddles") } }
    var defaultPreset: TablePreset { didSet { d.set(defaultPreset.rawValue, forKey: "preset") } }
    var defaultSeats: Int { didSet { d.set(defaultSeats, forKey: "seats") } }

    init() {
        apiKey = KeyStore.read()
        model = d.string(forKey: "model") ?? ClaudeClient.models[0]
        effort = d.string(forKey: "effort") ?? "medium"
        botSpeed = d.object(forKey: "botSpeed") as? Double ?? 0.7
        fourColor = d.object(forKey: "fourColor") as? Bool ?? true
        instantFeedback = d.object(forKey: "instantFeedback") as? Bool ?? false
        autoDeal = d.object(forKey: "autoDeal") as? Bool ?? false
        heroStraddles = d.object(forKey: "heroStraddles") as? Bool ?? false
        defaultPreset = TablePreset(rawValue: d.string(forKey: "preset") ?? "") ?? .typical
        defaultSeats = d.object(forKey: "seats") as? Int ?? 9
    }

    var hasKey: Bool { ClaudeClient.resolveKey(apiKey) != nil }
}

/// One "Ask Claude" thread. Each follow-up is sent as a fresh single-turn request carrying the prior Q&A as text.
@MainActor
@Observable
final class CoachChat: Identifiable {
    let id = UUID()
    let title: String
    let context: String
    var turns: [(question: String, answer: String)] = []
    var isStreaming = false
    var error: String?
    private var task: Task<Void, Never>?

    init(title: String, context: String) {
        self.title = title
        self.context = context
    }

    func ask(_ question: String, settings: AppSettings) {
        guard let key = ClaudeClient.resolveKey(settings.apiKey) else {
            error = ClaudeError.noKey.localizedDescription
            return
        }
        error = nil
        var prompt = context + "\n\n"
        for t in turns { prompt += "Earlier question: \(t.question)\nYour earlier answer: \(t.answer)\n\n" }
        prompt += "Question: \(question)"
        turns.append((question, ""))
        let idx = turns.count - 1
        isStreaming = true
        let client = ClaudeClient(apiKey: key, model: settings.model, effort: settings.effort)
        task = Task {
            do {
                for try await chunk in client.stream(system: ClaudeClient.systemPrompt, prompt: prompt) {
                    turns[idx].answer += chunk
                }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            isStreaming = false
        }
    }

    func cancel() {
        task?.cancel()
        isStreaming = false
    }
}

@MainActor
@Observable
final class AppModel {
    var screen: Screen = .home
    var modal: Modal?
    var showOnboarding = !UserDefaults.standard.bool(forKey: "onboarded") || ProcessInfo.processInfo.environment["HT_ONBOARDING"] != nil
    var workout: WorkoutSession?
    /// Deep link into Exploit Drills with a concept preselected.
    var drillConcept: DrillConcept?

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        showOnboarding = false
    }

    func openDrill(_ c: DrillConcept?) {
        drillConcept = c
        screen = .drills
    }
    let settings = AppSettings()
    let store = ProgressStore()
    let live: GameController
    let reads: GameController
    var chat: CoachChat?

    init() {
        if let s = ProcessInfo.processInfo.environment["HT_SCREEN"], let sc = Screen(rawValue: s) { screen = sc }
        live = GameController(mode: .play, preset: settings.defaultPreset, seats: settings.defaultSeats, settings: settings, store: store)
        reads = GameController(mode: .reads, preset: .random, settings: settings, store: store)
    }

    func openChat(title: String, context: String, question: String) {
        let c = CoachChat(title: title, context: context)
        chat = c
        c.ask(question, settings: settings)
    }
}
