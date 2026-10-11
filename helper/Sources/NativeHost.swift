import ApplicationServices
import Foundation

struct HostError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Chrome native messaging: one request per process. Messages are a 4-byte
/// native-endian length followed by UTF-8 JSON, on stdin and stdout.
enum NativeHost {
    /// Bumped when the extension needs new host behavior.
    static let protocolVersion = 2
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    static let accessibilityMessage =
        "Commonplace Helper needs Accessibility access to paste into Notes. Open Commonplace Helper, or allow it in System Settings › Privacy & Security › Accessibility."
    static let automationMessage =
        "Commonplace Helper isn't allowed to control Notes or System Events. Open Commonplace Helper, or allow it in System Settings › Privacy & Security › Automation."

    static func run(origin: String) -> Never {
        guard let message = readMessage() else { exit(0) }
        var response: [String: Any]
        do {
            guard Registration.isAllowed(origin: origin) else { throw HostError("Unknown caller.") }
            response = try handle(message)
            response["status"] = "ok"
        } catch {
            response = ["status": "error", "error": error.localizedDescription]
        }
        response["version"] = version
        response["protocol"] = protocolVersion
        writeMessage(response)
        exit(0)
    }

    static func handle(_ message: [String: Any]) throws -> [String: Any] {
        switch message["action"] as? String {
        case "ping":
            return ["accessibility": AXIsProcessTrusted()]
        case "list":
            let output = try runJXA(Scripts.list)
            guard let data = output.data(using: .utf8),
                  let notes = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw HostError("Couldn't read the list of notes.") }
            return ["notes": notes]
        case "append":
            try append(
                noteID: message["note_id"] as? String ?? "",
                title: message["title"] as? String ?? "",
                url: message["url"] as? String ?? "",
                comment: message["comment"] as? String ?? ""
            )
            return [:]
        case let action:
            throw HostError("Unknown action: \(action ?? "none")")
        }
    }

    static func append(noteID: String, title: String, url: String, comment: String) throws {
        guard noteID.range(of: #"^x-coredata://[\w-]+/\w+/p\d+$"#, options: .regularExpression) != nil else {
            throw HostError("Invalid note ID.")
        }
        // Fail before Notes is brought forward (which can close the extension popup)
        guard AXIsProcessTrusted() else { throw HostError(accessibilityMessage) }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let timestamp = formatter.string(from: Date())
        var html = "<div><br></div>"
            + "<div><b><a href=\"\(escape(url))\">\(escape(title.isEmpty ? url : title))</a></b></div>"
            + "<div>\(escape(url))</div>"
            + "<div>\(escape(timestamp))</div>"
        if !comment.isEmpty {
            let lines = comment.replacingOccurrences(of: "\r\n", with: "\n")
                .components(separatedBy: "\n").map(escape)
            html += "<div>[\(lines.joined(separator: "<br>"))]</div>"
        }

        let input = try JSONSerialization.data(withJSONObject: ["noteId": noteID, "html": html])
        let output = try runJXA(Scripts.append, argument: String(decoding: input, as: UTF8.self))
        let result = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
        if result?["verified"] as? Bool != true {
            throw HostError("Paste may have failed — Notes did not register a change. Try with Notes open.")
        }
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#x27;")
    }

    // MARK: - osascript

    static func runJXA(_ script: String, argument: String? = nil, timeout: TimeInterval = 30) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script] + (argument.map { [$0] } ?? [])
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()

        // Drain the pipes while waiting: the notes list is larger than a pipe buffer
        var out = Data()
        var err = Data()
        let reading = DispatchGroup()
        DispatchQueue.global().async(group: reading) { out = stdout.fileHandleForReading.readDataToEndOfFile() }
        DispatchQueue.global().async(group: reading) { err = stderr.fileHandleForReading.readDataToEndOfFile() }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw HostError("Notes didn't respond in time. If macOS is showing a permission prompt, answer it and try again.")
        }
        reading.wait()

        if process.terminationStatus != 0 {
            throw HostError(explain(String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func explain(_ stderr: String) -> String {
        // -1719 also means "invalid index", so match the Accessibility error by its text
        if ["(1002)", "assistive access", "not allowed to send keystrokes"].contains(where: stderr.contains) {
            return accessibilityMessage
        }
        if stderr.contains("(-1743)") {
            return automationMessage
        }
        // Errors thrown from the JXA come back as "execution error: Error: <message> (-2700)"
        if let match = stderr.range(of: #"^execution error: (Error: )+"#, options: .regularExpression),
           stderr.hasSuffix(" (-2700)") {
            return String(stderr[match.upperBound...].dropLast(" (-2700)".count))
        }
        return stderr
    }

    // MARK: - Framing

    static func readMessage() -> [String: Any]? {
        let input = FileHandle.standardInput
        guard let header = read(input, count: 4) else { return nil }
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard let body = read(input, count: Int(length)) else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    static func read(_ handle: FileHandle, count: Int) -> Data? {
        var data = Data()
        while data.count < count {
            guard let chunk = try? handle.read(upToCount: count - data.count), !chunk.isEmpty else { return nil }
            data.append(chunk)
        }
        return data
    }

    static func writeMessage(_ object: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: object) else { return }
        var length = UInt32(body.count)
        let output = FileHandle.standardOutput
        output.write(Data(bytes: &length, count: 4))
        output.write(body)
    }
}
