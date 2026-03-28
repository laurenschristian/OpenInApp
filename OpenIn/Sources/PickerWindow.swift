import SwiftUI
import AppKit

struct PickerView: View {
    let url: URL
    let browsers: [Browser]
    let sourceApp: String?
    let lastUsedBrowserID: String?
    let onPick: (Browser) -> Void
    let onDismiss: () -> Void
    @State private var editableURL: String
    @State private var hoveredID: String?
    @State private var copied = false
    @State private var isPresented = false

    init(url: URL, browsers: [Browser], sourceApp: String?, lastUsedBrowserID: String?, onPick: @escaping (Browser) -> Void, onDismiss: @escaping () -> Void) {
        self.url = url
        self.browsers = browsers
        self.sourceApp = sourceApp
        self.lastUsedBrowserID = lastUsedBrowserID
        self.onPick = onPick
        self.onDismiss = onDismiss
        self._editableURL = State(initialValue: url.absoluteString)
    }

    private var resolvedURL: URL {
        URL(string: editableURL) ?? url
    }

    var body: some View {
        ZStack {
            // Full-screen blur backdrop — click to dismiss
            Color.black.opacity(isPresented ? 0.35 : 0)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Centered card
            VStack(spacing: 16) {
                // URL bar
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)

                    TextField("URL", text: $editableURL)
                        .font(.system(size: 13, design: .monospaced))
                        .textFieldStyle(.plain)
                        .lineLimit(1)

                    Button(action: copyURL) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(copied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )

                // Source app
                if let sourceApp = sourceApp {
                    HStack(spacing: 5) {
                        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: sourceApp) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                                .resizable()
                                .frame(width: 14, height: 14)
                        }
                        Text("from \(appName(for: sourceApp))")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }

                // Browser grid
                let gridColumns = [GridItem(.adaptive(minimum: 80), spacing: 12)]
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(Array(sortedBrowsers.enumerated()), id: \.element.id) { index, browser in
                        BrowserCard(
                            browser: browser,
                            index: index + 1,
                            isHovered: hoveredID == browser.id,
                            isLastUsed: browser.id == lastUsedBrowserID,
                            action: { onPick(browser) }
                        )
                        .onHover { hoveredID = $0 ? browser.id : nil }
                    }
                }
            }
            .frame(maxWidth: 480)
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.5), radius: 40, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            )
            .opacity(isPresented ? 1 : 0)
            .scaleEffect(isPresented ? 1 : 0.92)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.18)) {
                isPresented = true
            }
        }
    }

    private var sortedBrowsers: [Browser] {
        guard let lastUsed = lastUsedBrowserID else { return browsers }
        var sorted = browsers
        if let idx = sorted.firstIndex(where: { $0.id == lastUsed }), idx > 0 {
            let browser = sorted.remove(at: idx)
            sorted.insert(browser, at: 0)
        }
        return sorted
    }

    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(editableURL, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func appName(for bundleID: String) -> String {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }
}

struct BrowserCard: View {
    let browser: Browser
    let index: Int
    let isHovered: Bool
    let isLastUsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: browser.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .scaleEffect(isHovered ? 1.1 : 1.0)
                        .animation(.easeOut(duration: 0.12), value: isHovered)

                    if let profileName = browser.profileName {
                        Text(String(profileName.prefix(2)).uppercased())
                            .font(.system(size: 7, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(profileColor(for: profileName))
                            .clipShape(Circle())
                            .offset(x: 4, y: 4)
                    }
                }

                Text(browser.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 80)

                // Simple number shortcut — just the number, no Cmd
                if index >= 1 && index <= 9 {
                    Text("\(index)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(.quaternary.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? .white.opacity(0.1) : .clear)
            )
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isLastUsed ? .blue.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func profileColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .indigo]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - Window Controller

final class PickerWindowController {
    static let shared = PickerWindowController()
    private var window: NSWindow?
    private var localMonitor: Any?
    private var completionHandler: ((Browser?) -> Void)?

    func show(url: URL, browsers: [Browser], sourceApp: String? = nil, completion: @escaping (Browser?) -> Void) {
        dismiss()

        self.completionHandler = completion
        let lastUsed = RulesEngine.shared.lastUsedBrowser(forHost: url.host ?? "")

        let pickerView = PickerView(
            url: url,
            browsers: browsers,
            sourceApp: sourceApp,
            lastUsedBrowserID: lastUsed,
            onPick: { [weak self] browser in
                self?.finish(with: browser)
            },
            onDismiss: { [weak self] in
                self?.finish(with: nil)
            }
        )

        // Full-screen window covering the entire screen
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        let hostingView = NSHostingView(rootView: pickerView)

        let w = PickerPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        w.contentView = hostingView
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        w.becomesKeyOnlyIfNeeded = false
        w.setFrame(screenFrame, display: true)

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w

        w.onEscape = { [weak self] in
            self?.finish(with: nil)
        }

        // Number keys 1-9 to pick browser directly (no Cmd needed)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.finish(with: nil)
                return nil
            }
            // Check for number keys 1-9
            if let chars = event.charactersIgnoringModifiers,
               let num = Int(chars),
               num >= 1 && num <= 9 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                let sorted = self?.sortedBrowsers(browsers: browsers, lastUsed: lastUsed) ?? browsers
                if num <= sorted.count {
                    self?.finish(with: sorted[num - 1])
                    return nil
                }
            }
            return event
        }
    }

    private func sortedBrowsers(browsers: [Browser], lastUsed: String?) -> [Browser] {
        guard let lastUsed = lastUsed else { return browsers }
        var sorted = browsers
        if let idx = sorted.firstIndex(where: { $0.id == lastUsed }), idx > 0 {
            let browser = sorted.remove(at: idx)
            sorted.insert(browser, at: 0)
        }
        return sorted
    }

    private func finish(with browser: Browser?) {
        let handler = completionHandler
        completionHandler = nil
        handler?(browser)
        dismiss()
    }

    func dismiss() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
    }
}

final class PickerPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}
