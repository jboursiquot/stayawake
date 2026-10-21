import Foundation
import IOKit.ps

/// Wraps `pmset disablesleep`, which needs root. The app never prompts for a
/// password; it relies on the sudoers rule installed by scripts/install-lid-mode.sh
/// and fails closed (lid mode simply stays off) when that rule is absent.
enum LidControl {
    static let sudo = "/usr/bin/sudo"
    static let pmset = "/usr/bin/pmset"

    /// True when the sudoers rule lets us run `pmset disablesleep` without a password.
    static func isInstalled() -> Bool {
        run(sudo, ["-n", "-l", pmset, "disablesleep", "1"]).status == 0
    }

    /// Reads `pmset -g` (no privileges needed) and reports the SleepDisabled flag.
    static func isSleepDisabled() -> Bool {
        let output = run(pmset, ["-g"]).output
        return output.split(separator: "\n").contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("SleepDisabled") && t.hasSuffix("1")
        }
    }

    @discardableResult
    static func setSleepDisabled(_ disabled: Bool) -> Bool {
        run(sudo, ["-n", pmset, "disablesleep", disabled ? "1" : "0"]).status == 0
    }

    /// Detached shell that re-enables sleep if this app dies (crash, force-quit)
    /// or the deadline passes without the app acting. Terminated on normal stop.
    static func spawnWatchdog(deadline: Date?) -> Process? {
        let pid = ProcessInfo.processInfo.processIdentifier
        let deadlineEpoch = deadline.map { Int($0.timeIntervalSince1970) } ?? 0
        let script = """
        while kill -0 \(pid) 2>/dev/null; do
          if [ \(deadlineEpoch) -gt 0 ] && [ "$(date +%s)" -ge \(deadlineEpoch) ]; then break; fi
          sleep 15
        done
        \(sudo) -n \(pmset) disablesleep 0
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            return p
        } catch {
            return nil
        }
    }

    private static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return (-1, "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

enum PowerSource {
    /// True on AC power (or on a desktop Mac with no battery). Defaults to true
    /// if the power-source snapshot is unreadable.
    static func isOnAC() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return true }
        return (type as String) == kIOPMACPowerKey
    }
}
