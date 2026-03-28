import SwiftUI

@main
struct OpenInApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var browserManager = BrowserManager.shared
    @StateObject private var rulesEngine = RulesEngine.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(browserManager: browserManager, rulesEngine: rulesEngine)
        } label: {
            Image(systemName: "arrow.up.right.square")
        }

        Settings {
            SettingsView()
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var browserManager: BrowserManager
    @ObservedObject var rulesEngine: RulesEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !browserManager.isDefaultBrowser {
                Button("Set as Default Browser") {
                    browserManager.setAsDefaultBrowser()
                    browserManager.reload()
                }
                Divider()
            }

            Text("\(rulesEngine.config.rules.count) rules active")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            Divider()

            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit OpenIn") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
