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

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            // Top accent line
            LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)

            VStack(spacing: 10) {
                // Editable URL bar
                HStack(spacing: 6) {
                    TextField("URL", text: $editableURL)
                        .font(.system(size: 11, design: .monospaced))
                        .textFieldStyle(.plain)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button(action: copyURL) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(copied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy URL")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                )
                .padding(.horizontal, 14)
                .padding(.top, 12)

                // Source app
                if let sourceApp = sourceApp {
                    HStack(spacing: 4) {
                        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: sourceApp) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                                .resizable()
                                .frame(width: 12, height: 12)
                        }
                        Text("from \(appName(for: sourceApp))")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(.tertiary)
                }

                // Browser grid
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(sortedBrowsers.enumerated()), id: \.element.id) { index, browser in
                        BrowserButton(
                            browser: browser,
                            index: index + 1,
                            isHovered: hoveredID == browser.id,
                            isLastUsed: browser.id == lastUsedBrowserID,
                            action: { onPick(browser) }
                        )
                        .onHover { hoveredID = $0 ? browser.id : nil }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .frame(minWidth: 240)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .opacity(isPresented ? 1 : 0)
        .scaleEffect(isPresented ? 1 : 0.95)
        .onAppear {
            withAnimation(.easeOut(duration: 0.15)) {
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

struct BrowserButton: View {
    let browser: Browser
    let index: Int
    let isHovered: Bool
    let isLastUsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: browser.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .scaleEffect(isHovered ? 1.12 : 1.0)
                        .animation(.easeOut(duration: 0.12), value: isHovered)

                    // Profile badge
                    if let profileName = browser.profileName {
                        Text(String(profileName.prefix(2)))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(profileColor(for: profileName))
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                            .offset(x: 3, y: 3)
                    } else if isLastUsed {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: 2)
                    }
                }

                Text(browser.name)
                    .font(.system(size: 9, weight: isLastUsed ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 72)

                if index >= 1 && index <= 9 {
                    Text("\u{2318}\(index)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .modifier(OptionalKeyboardShortcut(index: index))
    }

    private func profileColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .indigo]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}

struct OptionalKeyboardShortcut: ViewModifier {
    let index: Int

    func body(content: Content) -> some View {
        if index >= 1 && index <= 9 {
            content.keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
        } else {
            content
        }
    }
}

// MARK: - Window Controller

final class PickerWindowController {
    static let shared = PickerWindowController()
    private var window: NSWindow?
    private var globalMonitor: Any?
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

        let hostingView = NSHostingView(rootView: pickerView)
        hostingView.setFrameSize(hostingView.fittingSize)

        let w = PickerPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        w.contentView = hostingView
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.hasShadow = false
        w.isMovableByWindowBackground = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]
        w.becomesKeyOnlyIfNeeded = false

        // Position near mouse
        let mouseLocation = NSEvent.mouseLocation
        let wSize = hostingView.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main

        if let screen = screen {
            let screenFrame = screen.visibleFrame
            var origin = NSPoint(
                x: mouseLocation.x - wSize.width / 2,
                y: mouseLocation.y - wSize.height / 2
            )
            origin.x = max(screenFrame.minX + 10, min(origin.x, screenFrame.maxX - wSize.width - 10))
            origin.y = max(screenFrame.minY + 10, min(origin.y, screenFrame.maxY - wSize.height - 10))
            w.setFrameOrigin(origin)
        }

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w

        w.onEscape = { [weak self] in
            self?.finish(with: nil)
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.finish(with: nil)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.finish(with: nil)
                return nil
            }
            return event
        }
    }

    private func finish(with browser: Browser?) {
        let handler = completionHandler
        completionHandler = nil
        handler?(browser)
        dismiss()
    }

    func dismiss() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
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
