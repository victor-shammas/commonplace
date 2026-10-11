import AppKit

// One binary, two modes:
// - Chrome launches it as the native messaging host, passing the caller's origin
//   ("chrome-extension://<id>/") as an argument. It handles one request and exits.
// - Opened by the user, it registers itself with installed browsers and shows the
//   setup window for the macOS permissions it needs.

let arguments = CommandLine.arguments.dropFirst()

if let origin = arguments.first(where: { $0.hasPrefix("chrome-extension://") }) {
    NativeHost.run(origin: origin)
} else if arguments.contains("--register") {
    for browser in Registration.registerAll() {
        print("Registered with \(browser)")
    }
    exit(0)
} else {
    Registration.registerAll()
    SetupWindow.run()
}
