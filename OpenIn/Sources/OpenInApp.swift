import SwiftUI

@main
struct OpenInApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var browserManager = BrowserManager.shared
    @ObservedObject private var rulesEngine = RulesEngine.shared

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

            // Recent URLs
            if !rulesEngine.recentURLs.isEmpty {
                Text("Recent")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                ForEach(rulesEngine.recentURLs.prefix(8)) { entry in
                    Button {
                        if let url = URL(string: entry.url),
                           let browser = browserManager.browser(for: entry.browserID) {
                            browser.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if let browser = browserManager.browser(for: entry.browserID) {
                                Image(nsImage: browser.icon)
                                    .resizable()
                                    .frame(width: 14, height: 14)
                            }
                            Text(compactURL(entry.url))
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
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

    private func compactURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        let host = url.host ?? ""
        let path = url.path
        if path.isEmpty || path == "/" {
            return host
        }
        let shortPath = path.count > 30 ? String(path.prefix(30)) + "..." : path
        return "\(host)\(shortPath)"
    }
}
