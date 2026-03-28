import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var rulesEngine = RulesEngine.shared
    @ObservedObject var browserManager = BrowserManager.shared
    @State private var selectedRuleID: String?
    @State private var showingRuleEditor = false
    @State private var editingRule: Rule?

    var body: some View {
        TabView {
            GeneralTab(rulesEngine: rulesEngine, browserManager: browserManager)
                .tabItem { Label("General", systemImage: "gear") }

            RulesTab(
                rulesEngine: rulesEngine,
                browserManager: browserManager,
                selectedRuleID: $selectedRuleID,
                showingRuleEditor: $showingRuleEditor,
                editingRule: $editingRule
            )
            .tabItem { Label("Rules", systemImage: "list.bullet") }

            URLRewritingTab(rulesEngine: rulesEngine)
                .tabItem { Label("URL Rewriting", systemImage: "wand.and.stars") }

            StatsTab(rulesEngine: rulesEngine)
                .tabItem { Label("Stats", systemImage: "chart.bar") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 480)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @ObservedObject var rulesEngine: RulesEngine
    @ObservedObject var browserManager: BrowserManager

    var body: some View {
        Form {
            Section {
                if browserManager.isDefaultBrowser {
                    Label("OpenIn is your default browser", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack {
                        Label("OpenIn is not the default browser", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Set as Default") {
                            browserManager.setAsDefaultBrowser()
                            browserManager.reload()
                        }
                    }
                }
            }

            Section("Behavior") {
                Picker("When no rule matches:", selection: Binding(
                    get: { rulesEngine.config.defaultBrowserID ?? "" },
                    set: {
                        rulesEngine.config.defaultBrowserID = $0.isEmpty ? nil : $0
                        rulesEngine.save()
                    }
                )) {
                    Text("Show Picker").tag("")
                    ForEach(browserManager.browserOptions) { browser in
                        Text(browser.name).tag(browser.id)
                    }
                }

                Toggle("Show picker when no rule matches", isOn: Binding(
                    get: { rulesEngine.config.showPickerOnNoMatch },
                    set: { rulesEngine.config.showPickerOnNoMatch = $0; rulesEngine.save() }
                ))

                Toggle("Launch at login", isOn: Binding(
                    get: { rulesEngine.config.launchAtLogin },
                    set: {
                        rulesEngine.config.launchAtLogin = $0
                        rulesEngine.save()
                        if $0 {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
                ))
            }

            Section("Detected Browsers") {
                ForEach(browserManager.browsers) { browser in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(nsImage: browser.icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(browser.name)
                            Spacer()
                            Text(browser.bundleID)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        let profiles = browserManager.browserOptions.filter {
                            $0.bundleID == browser.bundleID && $0.profileDir != nil
                        }
                        if !profiles.isEmpty {
                            ForEach(profiles) { profile in
                                HStack(spacing: 4) {
                                    Image(systemName: "person.circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    Text(profile.profileName ?? profile.profileDir ?? "")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.leading, 28)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Rules Tab

struct RulesTab: View {
    @ObservedObject var rulesEngine: RulesEngine
    @ObservedObject var browserManager: BrowserManager
    @Binding var selectedRuleID: String?
    @Binding var showingRuleEditor: Bool
    @Binding var editingRule: Rule?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedRuleID) {
                ForEach(rulesEngine.config.rules) { rule in
                    RuleRow(rule: rule, rulesEngine: rulesEngine, browserManager: browserManager)
                        .tag(rule.id)
                        .onTapGesture(count: 2) {
                            editingRule = rule
                            showingRuleEditor = true
                        }
                }
                .onMove { source, destination in
                    rulesEngine.config.rules.move(fromOffsets: source, toOffset: destination)
                    rulesEngine.save()
                }
            }

            Divider()

            HStack(spacing: 4) {
                Button(action: {
                    editingRule = nil
                    showingRuleEditor = true
                }) {
                    Image(systemName: "plus")
                }
                Button(action: {
                    if let id = selectedRuleID,
                       let rule = rulesEngine.config.rules.first(where: { $0.id == id }) {
                        editingRule = rule
                        showingRuleEditor = true
                    }
                }) {
                    Image(systemName: "pencil")
                }
                .disabled(selectedRuleID == nil)
                Button(action: deleteSelected) {
                    Image(systemName: "minus")
                }
                .disabled(selectedRuleID == nil)

                Spacer()

                Text("Double-click to edit")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
        }
        .sheet(isPresented: $showingRuleEditor) {
            RuleEditorView(
                browserManager: browserManager,
                existingRule: editingRule,
                onSave: { rule in
                    if let idx = rulesEngine.config.rules.firstIndex(where: { $0.id == rule.id }) {
                        rulesEngine.config.rules[idx] = rule
                    } else {
                        rulesEngine.config.rules.append(rule)
                    }
                    rulesEngine.save()
                }
            )
        }
    }

    private func deleteSelected() {
        guard let id = selectedRuleID else { return }
        rulesEngine.config.rules.removeAll { $0.id == id }
        rulesEngine.save()
        selectedRuleID = nil
    }
}

struct RuleRow: View {
    let rule: Rule
    @ObservedObject var rulesEngine: RulesEngine
    @ObservedObject var browserManager: BrowserManager

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { newVal in
                    if let idx = rulesEngine.config.rules.firstIndex(where: { $0.id == rule.id }) {
                        rulesEngine.config.rules[idx].enabled = newVal
                        rulesEngine.save()
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(rule.name)
                        .font(.system(size: 12, weight: .medium))
                    if rule.openIncognito {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 9))
                            .foregroundStyle(.purple)
                    }
                    if rule.browserProfile != nil {
                        Image(systemName: "person.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(.blue)
                    }
                }
                HStack(spacing: 4) {
                    Text(rule.isRegex ? "regex:" : "match:")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(rule.pattern)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if let source = rule.sourceAppBundleID, !source.isEmpty {
                        Text("from \(source)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if let browser = browserManager.browser(for: rule.targetBrowserID) {
                Image(nsImage: browser.icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(browser.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Rule Editor

struct RuleEditorView: View {
    @ObservedObject var browserManager: BrowserManager
    let existingRule: Rule?
    let onSave: (Rule) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var id: String = UUID().uuidString
    @State private var name = ""
    @State private var pattern = ""
    @State private var isRegex = false
    @State private var sourceApp = ""
    @State private var targetBrowserID = ""
    @State private var browserProfile = ""
    @State private var openIncognito = false

    var isEditing: Bool { existingRule != nil }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Edit Rule" : "New Rule")
                .font(.headline)

            Form {
                TextField("Name:", text: $name)
                TextField("Pattern:", text: $pattern)
                    .font(.system(.body, design: .monospaced))
                Toggle("Use regex", isOn: $isRegex)
                TextField("Source app (bundle ID, optional):", text: $sourceApp)
                    .font(.system(.body, design: .monospaced))

                Picker("Open with:", selection: $targetBrowserID) {
                    Text("Select...").tag("")
                    ForEach(browserManager.browsers) { browser in
                        Text(browser.name).tag(browser.bundleID)
                    }
                }

                TextField("Browser profile (optional):", text: $browserProfile)
                    .font(.system(.body, design: .monospaced))

                Toggle("Open in private/incognito mode", isOn: $openIncognito)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save" : "Add Rule") {
                    let rule = Rule(
                        id: id,
                        name: name.isEmpty ? pattern : name,
                        pattern: pattern,
                        isRegex: isRegex,
                        sourceAppBundleID: sourceApp.isEmpty ? nil : sourceApp,
                        targetBrowserID: targetBrowserID,
                        browserProfile: browserProfile.isEmpty ? nil : browserProfile,
                        openIncognito: openIncognito
                    )
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pattern.isEmpty || targetBrowserID.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            if let rule = existingRule {
                id = rule.id
                name = rule.name
                pattern = rule.pattern
                isRegex = rule.isRegex
                sourceApp = rule.sourceAppBundleID ?? ""
                targetBrowserID = rule.targetBrowserID
                browserProfile = rule.browserProfile ?? ""
                openIncognito = rule.openIncognito
            }
        }
    }
}

// MARK: - URL Rewriting Tab

struct URLRewritingTab: View {
    @ObservedObject var rulesEngine: RulesEngine

    var body: some View {
        Form {
            Section("Automatic Cleanup") {
                Toggle("Strip tracking parameters (utm_*, fbclid, gclid, etc.)", isOn: Binding(
                    get: { rulesEngine.config.stripTrackingParams },
                    set: { rulesEngine.config.stripTrackingParams = $0; rulesEngine.save() }
                ))

                Toggle("Force HTTPS", isOn: Binding(
                    get: { rulesEngine.config.forceHTTPS },
                    set: { rulesEngine.config.forceHTTPS = $0; rulesEngine.save() }
                ))
            }

            Section("Tracking Parameters Removed") {
                Text(AppConfig.defaultTrackingParams.joined(separator: ", "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Stats Tab

struct StatsTab: View {
    @ObservedObject var rulesEngine: RulesEngine

    private var stats: AppConfig.Stats { rulesEngine.config.stats }

    private var topDomains: [(String, Int)] {
        stats.domainCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ($0.key, $0.value) }
    }

    private var topBrowsers: [(String, Int)] {
        stats.browserCounts
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Total URLs routed")
                    Spacer()
                    Text("\(stats.totalURLsRouted)")
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
            }

            Section("Top Domains") {
                if topDomains.isEmpty {
                    Text("No data yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(topDomains, id: \.0) { domain, count in
                        HStack {
                            Text(domain)
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Text("\(count)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Browsers") {
                if topBrowsers.isEmpty {
                    Text("No data yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(topBrowsers, id: \.0) { browser, count in
                        HStack {
                            Text(browser)
                            Spacer()
                            Text("\(count)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("Reset Stats", role: .destructive) {
                    rulesEngine.config.stats = AppConfig.Stats()
                    rulesEngine.save()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("OpenIn")
                .font(.title)
                .fontWeight(.bold)
            Text("v1.3.0")
                .foregroundStyle(.secondary)
            Text("A fast, native URL router for macOS")
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button("GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/laurenschristian/OpenInApp")!)
                }
                Button("Config File") {
                    NSWorkspace.shared.selectFile(AppConfig.configURL.path, inFileViewerRootedAtPath: "")
                }
            }
            .padding(.top, 4)

            Text("Cmd+Shift+B to open browser picker")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer()
            Text("Config: ~/.config/openin/config.json")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
    }
}
