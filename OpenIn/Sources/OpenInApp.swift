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

    private var braveProfiles: [Browser] {
        browserManager.browserOptions.filter { $0.bundleID.lowercased().contains("brave") && $0.profileDir != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !browserManager.isDefaultBrowser {
                Button("Set as Default Browser") {
                    browserManager.setAsDefaultBrowser()
                    browserManager.reload()
                }
                Divider()
            }

            // Stats
            let stats = rulesEngine.config.stats
            if stats.totalURLsRouted > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                    Text("\(stats.totalURLsRouted) URLs routed")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                Divider()
            }

            // Brave profiles quick-switch
            if !braveProfiles.isEmpty {
                Text("Brave Profiles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                ForEach(braveProfiles) { profile in
                    Button {
                        rulesEngine.config.defaultBrowserID = profile.bundleID
                        rulesEngine.config.defaultBrowserProfile = profile.profileDir
                        rulesEngine.save()
                    } label: {
                        HStack(spacing: 6) {
                            Image(nsImage: profile.icon)
                                .resizable()
                                .frame(width: 14, height: 14)
                            Text(profile.profileName ?? profile.name)
                                .font(.system(size: 11))
                            Spacer()
                            if rulesEngine.config.defaultBrowserID == profile.bundleID &&
                               rulesEngine.config.defaultBrowserProfile == profile.profileDir {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
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

            // Info row
            HStack(spacing: 8) {
                Text("\(rulesEngine.config.rules.count) rules active")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\u{2318}\u{21E7}B picker")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Check for Updates...") {
                (NSApp.delegate as? AppDelegate)?.updaterController.checkForUpdates(nil)
            }

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
