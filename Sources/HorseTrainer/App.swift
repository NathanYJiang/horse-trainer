import AppKit
import PokerCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched via `swift run` (no app bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct HorseTrainerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app: AppModel

    init() {
        FontLoader.registerBundledFonts()
        Snapshot.runIfRequested()
        _app = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup("Horse Trainer") {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .font(Theme.ui(13))
                .foregroundStyle(Theme.text)
                .tint(Theme.text)
                .frame(minWidth: 1360, minHeight: 820)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    app.live.endSession()
                    app.training.endSession()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1560, height: 960)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            HStack(spacing: 0) {
                Sidebar()
                    .frame(width: 224)
                Rectangle().fill(Theme.border).frame(width: 1).ignoresSafeArea()
                detail
                    .id(app.screen)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 8)
            }
            if let m = app.modal { modalLayer(m) }
            navKeys
            if let chat = app.chat { ChatDrawer(chat: chat) }
            if app.showOnboarding { OnboardingView().transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.14), value: app.screen)
        .animation(.easeOut(duration: 0.18), value: app.modal?.id)
        .animation(.easeOut(duration: 0.18), value: app.chat?.id)
        .animation(.easeOut(duration: 0.2), value: app.showOnboarding)
    }

    /// Hidden ⌘↑ / ⌘↓ to move through the sidebar.
    var navKeys: some View {
        ZStack {
            Button("") { app.moveScreen(-1) }.keyboardShortcut(.upArrow, modifiers: .command)
            Button("") { app.moveScreen(1) }.keyboardShortcut(.downArrow, modifiers: .command)
        }
        .buttonStyle(.plain)
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }

    @ViewBuilder var detail: some View {
        switch app.screen {
        case .home: HomeView()
        case .workout: WorkoutView()
        case .live: LiveTableScreen(game: app.live).id("live")
        case .training: LiveTableScreen(game: app.training).id("training")
        case .reads: LiveTableScreen(game: app.reads).id("reads")
        case .tracker: TrackerView()
        case .drills: DrillsView()
        case .sizing: SizingLabView()
        case .ranges: RangeBuilderView()
        case .equity: EquityView()
        case .playbook: PlaybookView()
        case .progress: ProgressScreen()
        case .settings: SettingsScreen()
        }
    }

    @ViewBuilder
    func modalLayer(_ m: Modal) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { app.modal = nil }
            switch m {
            case .newTable(let g): NewTableSheet(game: g)
            case .quiz(let g): if let q = g.quiz { QuizResultView(result: q) { g.dismissQuiz(); app.modal = nil } }
            case .sessionReport(let g, let startNew): SessionReportView(game: g, startNewAfter: startNew)
            }
        }
        .transition(.opacity)
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.text)
                    .frame(width: 24, height: 24)
                    .overlay(Image(systemName: "suit.spade.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.bg))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Horse Trainer").font(Theme.ui(14, .semibold))
                    Text("live 1/2 gym").font(Theme.mono(10)).foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 40)
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 2) {
                    item(.home)
                    item(.workout, badge: app.store.activeToday ? nil : "today")
                    group("Play")
                    item(.live)
                    item(.tracker)
                    group("Train")
                    item(.training)
                    item(.reads)
                    item(.drills)
                    item(.sizing)
                    item(.ranges)
                    item(.equity)
                    group("Learn")
                    item(.playbook)
                    item(.progress)
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").font(.system(size: 12)).foregroundStyle(app.store.streak > 0 ? Theme.flame : Theme.textFaint)
                    Text("\(app.store.streak)").font(Theme.mono(12, .semibold)).foregroundStyle(app.store.streak > 0 ? Theme.flame : Theme.textDim)
                    Spacer()
                    Text("Lv \(app.store.level) · \(app.store.levelTitle)").font(Theme.mono(11)).foregroundStyle(Theme.textDim)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.surface3)
                        RoundedRectangle(cornerRadius: 2).fill(Theme.duoPurple).frame(width: g.size.width * min(1, max(0, app.store.levelProgress)))
                    }
                }
                .frame(height: 4)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
            .padding(.horizontal, 10)
            HStack(spacing: 2) {
                footerButton("Guide", "questionmark.circle") { app.showOnboarding = true }
                footerButton("Settings", "gearshape", active: app.screen == .settings) { app.screen = .settings }
            }
            .padding(10)
        }
        .background(Theme.bg)
    }

    func group(_ title: String) -> some View {
        SectionLabel(title).padding(.horizontal, 8).padding(.top, 16).padding(.bottom, 4)
    }

    func item(_ s: Screen, badge: String? = nil) -> some View {
        let active = app.screen == s
        return Button {
            app.screen = s
        } label: {
            HStack(spacing: 10) {
                Image(systemName: s.icon).font(.system(size: 12, weight: .medium)).frame(width: 16)
                Text(s.title).font(Theme.ui(13, active ? .medium : .regular))
                Spacer()
                if let badge {
                    Text(badge).font(Theme.mono(9.5)).foregroundStyle(Theme.bg)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Theme.text))
                }
            }
            .foregroundStyle(active ? Theme.text : Theme.textDim)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Theme.radiusSm).fill(active ? Theme.surface2 : .clear))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(active ? Theme.border : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(s.blurb)
        .modifier(OptionalShortcut(key: s.shortcut))
    }

    func footerButton(_ title: String, _ icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(Theme.ui(12.5))
            }
            .foregroundStyle(active ? Theme.text : Theme.textDim)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Theme.radiusSm).fill(active ? Theme.surface2 : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct OptionalShortcut: ViewModifier {
    let key: KeyEquivalent?
    func body(content: Content) -> some View {
        if let key { content.keyboardShortcut(key, modifiers: .command) } else { content }
    }
}
