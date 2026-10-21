import AppKit
import Foundation
import IOKit.pwr_mgt
import ServiceManagement

/// Owns the power assertion, the countdown, and (optionally) lid-closed mode.
@MainActor
final class SleepKeeper: ObservableObject {
    static let presetHours = [1, 2, 3, 5, 8, 12, 15]

    @Published private(set) var isActive = false
    @Published private(set) var endsAt: Date?
    @Published private(set) var lidModeActive = false
    @Published private(set) var lidModeInstalled = LidControl.isInstalled()
    @Published private(set) var onACPower = PowerSource.isOnAC()
    @Published private(set) var loginItemStatus = SMAppService.mainApp.status
    @Published private(set) var lastError: String?
    @Published private(set) var now = Date()

    @Published var lidModeRequested: Bool {
        didSet {
            defaults.set(lidModeRequested, forKey: Keys.lidModeRequested)
            if lidModeRequested { lidModeInstalled = LidControl.isInstalled() }
            reconcileLidMode()
        }
    }

    @Published var showTimeInMenuBar: Bool {
        didSet { defaults.set(showTimeInMenuBar, forKey: Keys.showTimeInMenuBar) }
    }

    /// Bound directly to the menu toggle. Setting it registers/unregisters the
    /// login item; the value is then re-read from the system so the checkmark
    /// always reflects what macOS actually has.
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard !syncingLoginItem, launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                lastError = nil
            } catch {
                lastError = "Launch at login: \(error.localizedDescription)"
            }
            refreshLoginItemStatus()
        }
    }
    private var syncingLoginItem = false

    private enum Keys {
        static let lidModeRequested = "lidModeRequested"
        static let showTimeInMenuBar = "showTimeInMenuBar"
    }

    private let defaults = UserDefaults.standard
    private var assertionID = IOPMAssertionID(0)
    private var timer: Timer?
    private var watchdog: Process?

    init() {
        lidModeRequested = defaults.bool(forKey: Keys.lidModeRequested)
        showTimeInMenuBar = defaults.bool(forKey: Keys.showTimeInMenuBar)

        // A crash while lid mode was on leaves sleep disabled system-wide. Clear it.
        if LidControl.isSleepDisabled() {
            if !LidControl.setSleepDisabled(false) {
                lastError = "Sleep is disabled system-wide; run: sudo pmset disablesleep 0"
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }

        // Re-read external state each time the menu opens: login-item status can
        // change in System Settings, the sudoers rule can be installed, power can flip.
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshExternalState() }
        }
    }

    private func refreshExternalState() {
        now = Date()
        onACPower = PowerSource.isOnAC()
        if lidModeRequested, !lidModeInstalled { lidModeInstalled = LidControl.isInstalled() }
        refreshLoginItemStatus()
    }

    // MARK: - Session control

    func start(hours: Int?) {
        stop()
        let seconds: TimeInterval = hours.map { TimeInterval($0) * 3600 } ?? 0
        let reason = hours.map { "Keep awake for \($0)h" } ?? "Keep awake indefinitely"

        var id = IOPMAssertionID(0)
        let rc = IOPMAssertionCreateWithDescription(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            "StayAwake" as CFString,
            reason as CFString,
            nil, nil,
            seconds,                                   // 0 = no timeout
            seconds > 0 ? (kIOPMAssertionTimeoutActionRelease as CFString) : nil,
            &id)
        guard rc == kIOReturnSuccess else {
            lastError = "Could not create power assertion (IOReturn \(rc))"
            return
        }

        assertionID = id
        isActive = true
        endsAt = seconds > 0 ? Date().addingTimeInterval(seconds) : nil
        lastError = nil

        let t = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 5
        timer = t
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if isActive {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        isActive = false
        endsAt = nil
        reconcileLidMode()
    }

    private func tick() {
        now = Date()
        onACPower = PowerSource.isOnAC()
        if let endsAt, now >= endsAt {
            stop()
            return
        }
        reconcileLidMode()
    }

    // MARK: - Lid-closed mode (pmset disablesleep via sudoers rule)

    private func reconcileLidMode() {
        let want = isActive && lidModeRequested && onACPower && lidModeInstalled
        guard want != lidModeActive else { return }

        if want {
            if LidControl.setSleepDisabled(true) {
                lidModeActive = true
                watchdog = LidControl.spawnWatchdog(deadline: endsAt)
            } else {
                lastError = "Could not disable lid sleep (sudoers rule missing?)"
                lidModeInstalled = false
            }
        } else {
            if !LidControl.setSleepDisabled(false) {
                lastError = "Could not re-enable sleep; run: sudo pmset disablesleep 0"
            }
            lidModeActive = false
            watchdog?.terminate()
            watchdog = nil
        }
    }

    // MARK: - Launch at login

    private func refreshLoginItemStatus() {
        let status = SMAppService.mainApp.status
        loginItemStatus = status
        syncingLoginItem = true
        launchAtLogin = status == .enabled
        syncingLoginItem = false
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    var loginNote: String? {
        switch loginItemStatus {
        case .requiresApproval: return "Launch at login: needs approval in System Settings"
        default: return nil
        }
    }

    // MARK: - Presentation

    var symbolName: String {
        isActive ? "cup.and.saucer.fill" : "cup.and.saucer"
    }

    var statusLine: String {
        guard isActive else { return "Sleep allowed" }
        guard let endsAt else { return "Awake indefinitely" }
        return "Awake until \(Self.clock.string(from: endsAt)) · \(remaining(endsAt, short: false)) left"
    }

    var lidNote: String? {
        guard isActive, lidModeRequested else { return nil }
        if !lidModeInstalled { return "Closed lid: not set up (see README)" }
        if !onACPower { return "Closed lid: paused — on battery" }
        return lidModeActive ? "Closed lid: OK" : nil
    }

    var shortRemaining: String? {
        guard isActive else { return nil }
        guard let endsAt else { return "∞" }
        return remaining(endsAt, short: true)
    }

    private func remaining(_ date: Date, short: Bool) -> String {
        let total = max(0, Int(date.timeIntervalSince(now)))
        let h = total / 3600
        let m = (total % 3600) / 60
        if short { return h > 0 ? "\(h)h\(String(format: "%02d", m))m" : "\(m)m" }
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
}
