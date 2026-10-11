import Foundation

/// Writes the native messaging host manifest into every installed Chromium browser's
/// per-user NativeMessagingHosts directory, pointing at this binary. Run on every
/// launch so the registration follows the app if it is moved.
enum Registration {
    static let hostName = "com.victorshammas.commonplace"

    /// Extension IDs allowed to talk to the helper. Chrome doesn't accept wildcards.
    static let extensionIDs = [
        // Chrome Web Store ID. Unpacked dev builds get the same ID from the "key" in manifest.json.
        "pckjhgfeeiebcdegmgnllooegobohcoc",
    ]

    /// Display name and directory under ~/Library/Application Support.
    static let browsers: [(name: String, directory: String)] = [
        ("Google Chrome", "Google/Chrome"),
        ("Google Chrome Beta", "Google/Chrome Beta"),
        ("Google Chrome Dev", "Google/Chrome Dev"),
        ("Google Chrome Canary", "Google/Chrome Canary"),
        ("Chromium", "Chromium"),
        ("Brave", "BraveSoftware/Brave-Browser"),
        ("Microsoft Edge", "Microsoft Edge"),
        ("Vivaldi", "Vivaldi"),
        ("Arc", "Arc/User Data"),
    ]

    /// Returns the names of the browsers it registered with.
    @discardableResult
    static func registerAll() -> [String] {
        let fm = FileManager.default
        let support = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path else { return [] }

        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Commonplace Helper",
            "path": executable,
            "type": "stdio",
            "allowed_origins": extensionIDs.map { "chrome-extension://\($0)/" },
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return [] }

        var registered: [String] = []
        for browser in browsers {
            let browserDir = support.appendingPathComponent(browser.directory)
            // Only browsers that are installed (have a profile directory)
            guard fm.fileExists(atPath: browserDir.path) else { continue }
            let hostsDir = browserDir.appendingPathComponent("NativeMessagingHosts")
            do {
                try fm.createDirectory(at: hostsDir, withIntermediateDirectories: true)
                try data.write(to: hostsDir.appendingPathComponent("\(hostName).json"), options: .atomic)
                registered.append(browser.name)
            } catch {
                continue
            }
        }
        return registered
    }

    static func isAllowed(origin: String) -> Bool {
        extensionIDs.contains { origin == "chrome-extension://\($0)/" }
    }
}
