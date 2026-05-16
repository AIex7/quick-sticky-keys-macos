import AppKit
import ApplicationServices
import Foundation

private struct Modifier: Hashable {
    let name: String
    let flag: CGEventFlags
    let keyCodes: Set<Int64>

    static let shift = Modifier(name: "Shift", flag: .maskShift, keyCodes: [56, 60])
    static let control = Modifier(name: "Control", flag: .maskControl, keyCodes: [59, 62])
    static let option = Modifier(name: "Option", flag: .maskAlternate, keyCodes: [58, 61])
    static let command = Modifier(name: "Command", flag: .maskCommand, keyCodes: [55, 54])

    static let all: [Modifier] = [.shift, .control, .option, .command]

    static func == (lhs: Modifier, rhs: Modifier) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

private final class StickyModifierEngine {
    private let stickyDuration: TimeInterval = 1.0
    private var activeUntil: [Modifier: Date] = [:]
    private var physicallyDown: Set<Modifier> = []
    private var lastPhysicalFlags: CGEventFlags = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var activeModifierNames: String {
        pruneExpired()
        let names = activeUntil.keys.map(\.name).sorted()
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    func start() throws {
        guard AXIsProcessTrusted() else {
            throw StickyKeysError.accessibilityPermissionMissing
        }

        let mask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: context
        ) else {
            throw StickyKeysError.eventTapCreationFailed
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        self.runLoopSource = nil
        self.eventTap = nil
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        pruneExpired()

        switch type {
        case .flagsChanged:
            handleFlagsChanged(event)
            event.flags = mergedFlags(for: event.flags)
        case .keyDown:
            event.flags = mergedFlags(for: event.flags)
            clearStickyModifiersIfNeeded(for: event)
        case .keyUp:
            event.flags = mergedFlags(for: event.flags)
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard let modifier = Modifier.all.first(where: { $0.keyCodes.contains(keyCode) }) else {
            lastPhysicalFlags = event.flags
            return
        }

        let isDown = event.flags.contains(modifier.flag)
        if isDown {
            physicallyDown.insert(modifier)
            makeSticky(modifier)
        } else {
            physicallyDown.remove(modifier)
        }

        lastPhysicalFlags = event.flags
    }

    private func makeSticky(_ modifier: Modifier) {
        let requestedExpiry = Date().addingTimeInterval(stickyDuration)
        let currentLongest = activeUntil.values.max() ?? requestedExpiry
        let expiry = max(requestedExpiry, currentLongest)
        let modifiersToExtend = Set(activeUntil.keys).union([modifier])

        for activeModifier in modifiersToExtend {
            activeUntil[activeModifier] = expiry
        }
    }

    private func clearStickyModifiersIfNeeded(for event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isModifier = Modifier.all.contains { $0.keyCodes.contains(keyCode) }

        if !isModifier && !activeUntil.isEmpty {
            activeUntil.removeAll()
        }
    }

    private func mergedFlags(for flags: CGEventFlags) -> CGEventFlags {
        var merged = flags
        for (modifier, expiry) in activeUntil where expiry > Date() {
            merged.insert(modifier.flag)
        }
        return merged
    }

    private func pruneExpired() {
        let now = Date()
        activeUntil = activeUntil.filter { modifier, expiry in
            expiry > now || physicallyDown.contains(modifier)
        }
    }
}

private enum StickyKeysError: LocalizedError {
    case accessibilityPermissionMissing
    case eventTapCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "Accessibility permission is required to observe and rewrite keyboard events."
        case .eventTapCreationFailed:
            "Could not create the keyboard event tap."
        }
    }
}

private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let engine = Unmanaged<StickyModifierEngine>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return engine.handle(proxy: proxy, type: type, event: event)
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = StickyModifierEngine()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenu = NSMenu()
    private let statusItemTitle = NSMenuItem(title: "Active: None", action: nil, keyEquivalent: "")
    private var statusTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()

        do {
            try engine.start()
            setStatus("Sticky Keys")
        } catch {
            setStatus("Sticky Keys Off")
            showPermissionAlert(message: error.localizedDescription)
        }

        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
        engine.stop()
    }

    private func configureMenu() {
        if let button = statusItem.button {
            button.title = "Sticky Keys"
        }

        let openAccessibility = NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        openAccessibility.target = self

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        statusMenu.addItem(statusItemTitle)
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(openAccessibility)
        statusMenu.addItem(quit)
        statusItem.menu = statusMenu
    }

    private func refreshStatus() {
        statusItemTitle.title = "Active: \(engine.activeModifierNames)"
    }

    private func setStatus(_ title: String) {
        statusItem.button?.title = title
    }

    private func showPermissionAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Sticky Keys needs Accessibility access"
        alert.informativeText = "\(message)\n\nEnable it in System Settings, then relaunch the app."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
