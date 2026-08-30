import SwiftUI

@main
@MainActor
struct TelaApp: App {
    @State private var sessionStore: TelaSessionStore

    init() {
        _sessionStore = State(initialValue: TelaSessionStore())
    }

    var body: some Scene {
        WindowGroup("Tela", id: "main") {
            DashboardView()
                .environment(sessionStore)
                .frame(minWidth: 820, minHeight: 580)
        }
        .defaultSize(width: 1_160, height: 780)
        .windowStyle(.hiddenTitleBar)

        Window("Attività", id: "activity") {
            ActivityView()
                .environment(sessionStore)
        }
        .defaultSize(width: 900, height: 650)

#if TELA_DEMO
        Window("Studio Demo", id: "demo") {
            DemoStudioView()
        }
        .defaultSize(width: 1_280, height: 720)
        .windowStyle(.hiddenTitleBar)
#endif

        Settings {
            SettingsView()
                .environment(sessionStore)
        }

        MenuBarExtra {
            MenuBarTimerView()
                .environment(sessionStore)
        } label: {
            Label {
                Text(sessionStore.formattedRemaining)
                    .monospacedDigit()
            } icon: {
                Image(systemName: sessionStore.isRunning ? "timer" : "timer.square")
            }
        }
        .menuBarExtraStyle(.window)

        .commands {
            CommandMenu("Tela") {
                OpenWindowButton(title: "Attività", systemImage: "clock.arrow.circlepath", windowID: "activity")
                    .keyboardShortcut("h", modifiers: [.command, .shift])
#if TELA_DEMO
                OpenWindowButton(title: "Studio Demo", systemImage: "sparkles.rectangle.stack", windowID: "demo")
                    .keyboardShortcut("d", modifiers: [.command, .shift])
#endif
            }
        }
    }
}

private struct OpenWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    let title: String
    let systemImage: String
    let windowID: String

    var body: some View {
        Button {
            openWindow(id: windowID)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}
