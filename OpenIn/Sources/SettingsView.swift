import SwiftUI

struct SettingsView: View {
    @ObservedObject var rulesEngine = RulesEngine.shared
    @ObservedObject var browserManager = BrowserManager.shared
    @State private var selectedRuleID: String?
    @State private var showingAddRule = false

    var body: some View {
        TabView {
            GeneralTab(rulesEngine: rulesEngine, browserManager: browserManager)
                .tabItem { Label("General", systemImage: "gear") }

            RulesTab(
                rulesEngine: rulesEngine,
                browserManager: browserManager,
                selectedRuleID: $selectedRuleID,
                showingAddRule: $showingAddRule
            )
            .tabItem { Label("Rules", systemImage: "list.bullet") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 400)
    }
}

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

            Section("Default Browser") {
                Picker("When no rule matches, open with:", selection: Binding(
                    get: { rulesEngine.config.defaultBrowserID ?? "" },
                    set: {
                        rulesEngine.config.defaultBrowserID = $0.isEmpty ? nil : $0
                        rulesEngine.save()
                    }
                )) {
                    Text("Show Picker").tag("")
                    ForEach(browserManager.browsers) { browser in
                        Text(browser.name).tag(browser.bundleID)
                    }
                }

                Toggle("Show picker when no rule matches", isOn: Binding(
                    get: { rulesEngine.config.showPickerOnNoMatch },
                    set: {
                        rulesEngine.config.showPickerOnNoMatch = $0
                        rulesEngine.save()
                    }
                ))
            }

            Section("Detected Browsers") {
                ForEach(browserManager.browsers) { browser in
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
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct RulesTab: View {
    @ObservedObject var rulesEngine: RulesEngine
    @ObservedObject var browserManager: BrowserManager
    @Binding var selectedRuleID: String?
    @Binding var showingAddRule: Bool

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedRuleID) {
                ForEach(rulesEngine.config.rules) { rule in
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
                            Text(rule.name)
                                .font(.system(size: 12, weight: .medium))
                            HStack(spacing: 4) {
                                Text(rule.isRegex ? "regex:" : "match:")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                Text(rule.pattern)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
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
                    .tag(rule.id)
                }
                .onMove { source, destination in
                    rulesEngine.config.rules.move(fromOffsets: source, toOffset: destination)
                    rulesEngine.save()
                }
            }

            Divider()

            HStack {
                Button(action: { showingAddRule = true }) {
                    Image(systemName: "plus")
                }
                Button(action: deleteSelected) {
                    Image(systemName: "minus")
                }
                .disabled(selectedRuleID == nil)
                Spacer()
            }
            .padding(8)
        }
        .sheet(isPresented: $showingAddRule) {
            RuleEditorView(
                browserManager: browserManager,
                onSave: { rule in
                    rulesEngine.config.rules.append(rule)
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

struct RuleEditorView: View {
    @ObservedObject var browserManager: BrowserManager
    let onSave: (Rule) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var pattern = ""
    @State private var isRegex = false
    @State private var sourceApp = ""
    @State private var targetBrowserID = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("New Rule")
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
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Rule") {
                    let rule = Rule(
                        name: name.isEmpty ? pattern : name,
                        pattern: pattern,
                        isRegex: isRegex,
                        sourceAppBundleID: sourceApp.isEmpty ? nil : sourceApp,
                        targetBrowserID: targetBrowserID
                    )
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pattern.isEmpty || targetBrowserID.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

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
            Text("v1.0.0")
                .foregroundStyle(.secondary)
            Text("A fast, native URL router for macOS")
                .foregroundStyle(.secondary)
            Spacer()
            Text("Config: ~/.config/openin/config.json")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
    }
}
