import AppKit
import ApplicationServices
import SwiftUI

enum SetupWindow {
    static let extensionURL = URL(string: "https://victorshammas.com/apps/")!
    private static let delegate = AppDelegate()

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
        exit(0)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit Commonplace Helper",
                                 action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(appItem)
        NSApp.mainMenu = menu

        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Commonplace Helper"
        window.contentView = NSHostingView(rootView: SetupView(model: SetupModel()))
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Permissions

enum Permission: Equatable {
    case granted, denied, notDetermined, unknown
}

enum Permissions {
    static let notes = "com.apple.Notes"
    static let systemEvents = "com.apple.systemevents"

    /// Automation (Apple Events) permission for this app to control `bundleID`.
    /// With `ask`, shows the system prompt if the user hasn't decided yet (blocks).
    static func automation(_ bundleID: String, ask: Bool) -> Permission {
        var target = AEAddressDesc()
        let created = bundleID.withCString {
            AECreateDesc(typeApplicationBundleID, $0, strlen($0), &target)
        }
        guard created == noErr else { return .unknown }
        defer { AEDisposeDesc(&target) }
        switch AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        default: return .unknown // e.g. the target app isn't running
        }
    }

    /// Launches an app in the background so its Automation permission can be checked.
    static func launch(_ bundleID: String, then: @escaping () -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return then() }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in then() }
    }

    static func openSettings(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}

final class SetupModel: ObservableObject {
    @Published var browsers: [String] = []
    @Published var notes: Permission = .unknown
    @Published var systemEvents: Permission = .unknown
    @Published var accessibility = false
    private var timer: Timer?

    init() {
        browsers = Registration.registerAll()
        refresh()
        // Pick up changes the user makes in System Settings
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        accessibility = AXIsProcessTrusted()
        DispatchQueue.global().async {
            let notes = Permissions.automation(Permissions.notes, ask: false)
            let systemEvents = Permissions.automation(Permissions.systemEvents, ask: false)
            DispatchQueue.main.async {
                self.notes = notes
                self.systemEvents = systemEvents
            }
        }
    }

    func request(_ bundleID: String, current: Permission) {
        if current == .denied {
            // macOS won't ask again once denied; the user has to switch it on
            return Permissions.openSettings("Privacy_Automation")
        }
        Permissions.launch(bundleID) {
            DispatchQueue.global().async {
                _ = Permissions.automation(bundleID, ask: true)
                DispatchQueue.main.async { self.refresh() }
            }
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            Permissions.openSettings("Privacy_Accessibility")
        }
    }
}

// MARK: - View

struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Commonplace Helper").font(.title2.bold())
                    Text("Connects the Commonplace Chrome extension to Apple Notes. Allow the items below once; after that the helper runs only while you save a page.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                StepRow(
                    title: "Browser",
                    detail: model.browsers.isEmpty
                        ? "No supported browser found. Install Chrome, then open this app again."
                        : "Connected to \(model.browsers.joined(separator: ", ")).",
                    done: !model.browsers.isEmpty
                )
                StepRow(
                    title: "Notes",
                    detail: "Lists your notes and opens the one you pick.",
                    done: model.notes == .granted,
                    button: model.notes == .denied ? "Open Settings…" : "Allow…"
                ) { model.request(Permissions.notes, current: model.notes) }
                StepRow(
                    title: "System Events",
                    detail: "Pastes the entry at the end of the note.",
                    done: model.systemEvents == .granted,
                    button: model.systemEvents == .denied ? "Open Settings…" : "Allow…"
                ) { model.request(Permissions.systemEvents, current: model.systemEvents) }
                StepRow(
                    title: "Accessibility",
                    detail: "Needed to send the paste keystroke. Turn on Commonplace Helper in the list.",
                    done: model.accessibility,
                    button: "Open Settings…"
                ) { model.requestAccessibility() }
            }

            Divider()

            HStack {
                Link("Get the Chrome extension", destination: SetupWindow.extensionURL)
                Spacer()
                Button("Done") { NSApp.terminate(nil) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

struct StepRow: View {
    let title: String
    let detail: String
    let done: Bool
    var button: String? = nil
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let button, !done {
                Button(button, action: action)
            }
        }
    }
}
