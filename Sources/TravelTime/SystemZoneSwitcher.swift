import Foundation

enum ZoneSwitchError: LocalizedError {
    case scriptUnavailable
    case userCanceled
    case adminRejected(String)

    var errorDescription: String? {
        switch self {
        case .scriptUnavailable:
            return "Could not launch the osascript process"
        case .userCanceled:
            // Should never be shown — callers check for this case and stay silent.
            return nil
        case .adminRejected(let msg):
            let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Authorization failed: \(trimmed.isEmpty ? "unknown error" : trimmed)"
        }
    }
}

/// Runs a privileged command through the macOS authorization dialog (osascript subprocess).
/// Never blocks the main thread and never stores the password.
///
/// Execution happens on a background queue; the method returns after the child
/// finishes or after `timeout` seconds (whichever comes first). On timeout the
/// child process is terminated so a dismissed/ignored authorization dialog can
/// never leave a dangling osascript around.
enum PrivilegedRunner {
    static func run(script: String, timeout: TimeInterval = 15) async throws {
        let result = await Task.detached(priority: .userInitiated) {
            runBlocking(script: script, timeout: timeout)
        }.value
        let (status, output) = result

        if status == -1 {
            throw ZoneSwitchError.scriptUnavailable
        }
        if status == -2 {
            throw ZoneSwitchError.adminRejected("Timed out waiting for authorization")
        }
        if status != 0 {
            // osascript returns 128 when the user dismisses the authorization
            // dialog. That is the user explicitly saying "no thanks" — not an
            // error worth surfacing in the UI.
            if status == 128 || output.contains("User canceled") {
                throw ZoneSwitchError.userCanceled
            }
            throw ZoneSwitchError.adminRejected(output)
        }
    }

    /// Synchronous by design: it runs only inside a detached task. Keeping the
    /// blocking Process API out of an async context avoids Swift 6 executor
    /// starvation warnings while a DispatchWorkItem enforces the hard timeout.
    private static func runBlocking(script: String, timeout: TimeInterval) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do { try process.run() }
        catch { return (-1, "launch failed: \(error.localizedDescription)") }

        let lock = NSLock()
        var timedOut = false
        let timeoutWork = DispatchWorkItem {
            guard process.isRunning else { return }
            lock.lock(); timedOut = true; lock.unlock()
            process.terminate()
        }
        DispatchQueue.global(qos: .userInitiated)
            .asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutWork.cancel()
        lock.lock(); let didTimeOut = timedOut; lock.unlock()
        if didTimeOut { return (-2, "Timed out waiting for authorization") }
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

/// Abstraction over the privileged timezone switch so TimeZoneStore can be
/// unit-tested without triggering real admin prompts.
protocol ZoneSwitching {
    func switchTimeZone(to identifier: String) async throws
}

/// Real implementation: runs systemsetup through an osascript subprocess with
/// administrator privileges (see PrivilegedRunner).
struct SystemZoneSwitcher: ZoneSwitching {
    static let shared = SystemZoneSwitcher()

    /// Switches the system time zone.
    ///
    /// The identifier is validated against the system's known IANA list before
    /// it ever reaches a shell string — this is the primary defense against
    /// command injection via untrusted input (e.g. a spoofed geo-location
    /// response). After validation the value can only contain letters, digits,
    /// `_`, `/` and `-`, which are inert inside the quoted AppleScript string.
    func switchTimeZone(to identifier: String) async throws {
        guard TimeZone.knownTimeZoneIdentifiers.contains(identifier) else {
            throw ZoneSwitchError.adminRejected("Invalid time zone: \(identifier)")
        }
        let script = "do shell script \"/usr/sbin/systemsetup -settimezone '\(identifier)'\" with administrator privileges"
        try await PrivilegedRunner.run(script: script)
    }
}
