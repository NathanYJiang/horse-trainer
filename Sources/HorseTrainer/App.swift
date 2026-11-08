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
    @State private var app = AppModel()

    init() {
        Snapshot.runIfRequested()
    }

    var body: some Scene {
        WindowGroup("Horse Trainer") {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1360, minHeight: 820)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    app.live.endSession()
                }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1560, height: 960)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            List(selection: Binding(get: { app.screen }, set: { if let s = $0 { app.screen = s } })) {
                Section("Play") {
                    row(.live)
                    row(.reads)
                }
                Section("Train") {
                    row(.drills)
                    row(.sizing)
                    row(.ranges)
                    row(.equity)
                }
                Section("Learn") {
                    row(.playbook)
                    row(.progress)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .safeAreaInset(edge: .top, spacing: 8) { brand }
            .safeAreaInset(edge: .bottom) { footer }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
                .toolbar(removing: .title)
        }
        .sheet(item: $app.chat) { ClaudeChatSheet(chat: $0) }
    }

    var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Theme.red)
                Image(systemName: "suit.spade.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("Horse Trainer").font(.system(size: 14, weight: .semibold))
                Text("Live 1/2 exploit gym").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    var footer: some View {
        Button {
            app.screen = .settings
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                Text("Settings")
                Spacer()
                Circle().fill(app.settings.hasKey ? Theme.good : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
                    .help(app.settings.hasKey ? "Claude coach connected" : "Claude coach: no API key")
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 6).fill(app.screen == .settings ? Color.primary.opacity(0.12) : .clear))
        .padding(10)
    }

    func row(_ s: Screen) -> some View {
        Label(s.title, systemImage: s.icon).tag(s)
    }

    @ViewBuilder var detail: some View {
        switch app.screen {
        case .live:
            LiveTableScreen(game: app.live).id("live")
        case .reads:
            LiveTableScreen(game: app.reads).id("reads")
        case .drills: DrillsView()
        case .sizing: SizingLabView()
        case .ranges: RangeBuilderView()
        case .equity: EquityView()
        case .playbook: PlaybookView()
        case .progress: ProgressScreen()
        case .settings: SettingsScreen()
        }
    }
}
