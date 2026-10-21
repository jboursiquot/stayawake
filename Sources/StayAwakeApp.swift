import SwiftUI

@main
struct StayAwakeApp: App {
    @StateObject private var keeper = SleepKeeper()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(keeper: keeper)
        } label: {
            MenuBarLabel(keeper: keeper)
        }
    }
}

/// The icon in the menu bar. Swap the two symbol names in `SleepKeeper.symbolName`
/// to change it (e.g. eye / eye.fill, lightbulb / lightbulb.fill).
struct MenuBarLabel: View {
    @ObservedObject var keeper: SleepKeeper

    var body: some View {
        if keeper.showTimeInMenuBar, let short = keeper.shortRemaining {
            HStack(spacing: 4) {
                Image(systemName: keeper.symbolName)
                Text(short)
            }
        } else {
            Image(systemName: keeper.symbolName)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var keeper: SleepKeeper

    var body: some View {
        Text(keeper.statusLine)
        if let note = keeper.lidNote {
            Text(note)
        }
        if let error = keeper.lastError {
            Text("⚠︎ \(error)")
        }
        if keeper.isActive {
            Button("Turn Off") { keeper.stop() }
        }

        Divider()

        Text("Keep awake for")
        ForEach(SleepKeeper.presetHours, id: \.self) { hours in
            Button(hours == 1 ? "1 hour" : "\(hours) hours") { keeper.start(hours: hours) }
        }
        Button("Indefinitely") { keeper.start(hours: nil) }

        Divider()

        Toggle("Allow Closed Lid (AC power only)", isOn: $keeper.lidModeRequested)
        Toggle("Show Time in Menu Bar", isOn: $keeper.showTimeInMenuBar)
        Toggle("Launch at Login", isOn: $keeper.launchAtLogin)
        if let note = keeper.loginNote {
            Text(note)
            Button("Open Login Items Settings…") { keeper.openLoginItemsSettings() }
        }

        Divider()

        Button("Quit StayAwake") {
            keeper.stop()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
