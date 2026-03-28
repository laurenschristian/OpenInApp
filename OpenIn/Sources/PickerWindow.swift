import SwiftUI
import AppKit

struct PickerView: View {
    let url: URL
    let browsers: [Browser]
    let onPick: (Browser) -> Void
    let onDismiss: () -> Void
    @State private var hoveredID: String?

    var body: some View {
        VStack(spacing: 12) {
            // URL display
            Text(url.absoluteString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.top, 4)

            // Browser grid
            HStack(spacing: 16) {
                ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                    BrowserButton(
                        browser: browser,
                        index: index + 1,
                        isHovered: hoveredID == browser.id,
                        action: { onPick(browser) }
                    )
                    .onHover { hoveredID = $0 ? browser.id : nil }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 200)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .onExitCommand { onDismiss() }
    }
}

struct BrowserButton: View {
    let browser: Browser
    let index: Int
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(nsImage: browser.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .scaleEffect(isHovered ? 1.15 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: isHovered)

                Text(browser.name)
                    .font(.system(size: 10))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if index <= 9 {
                    Text("⌘\(index)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
    }
}

// MARK: - Window Controller

final class PickerWindowController {
    static let shared = PickerWindowController()
    private var window: NSWindow?
    private var monitor: Any?

    func show(url: URL, browsers: [Browser], completion: @escaping (Browser?) -> Void) {
        dismiss()

        let pickerView = PickerView(
            url: url,
            browsers: browsers,
            onPick: { [weak self] browser in
                completion(browser)
                self?.dismiss()
            },
            onDismiss: { [weak self] in
                completion(nil)
                self?.dismiss()
            }
        )

        let hostingView = NSHostingView(rootView: pickerView)
        hostingView.setFrameSize(hostingView.fittingSize)

        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.contentView = hostingView
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.hasShadow = false // We draw our own shadow
        w.isMovableByWindowBackground = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Center on screen at mouse location
        if let screen = NSScreen.main {
            let mouseLocation = NSEvent.mouseLocation
            let screenFrame = screen.frame
            let wSize = hostingView.fittingSize
            var origin = NSPoint(
                x: mouseLocation.x - wSize.width / 2,
                y: mouseLocation.y - wSize.height / 2
            )
            // Keep on screen
            origin.x = max(screenFrame.minX + 20, min(origin.x, screenFrame.maxX - wSize.width - 20))
            origin.y = max(screenFrame.minY + 20, min(origin.y, screenFrame.maxY - wSize.height - 20))
            w.setFrameOrigin(origin)
        }

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w

        // Click outside to dismiss
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            completion(nil)
            self?.dismiss()
        }
    }

    func dismiss() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        window?.orderOut(nil)
        window = nil
    }
}
