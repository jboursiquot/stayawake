# stayawake

Prevent laptop from sleeping. A menu bar app (cup icon) that holds a
`PreventUserIdleDisplaySleep` power assertion for 1 to 15 hours or indefinitely.

## Build

Needs only the Xcode Command Line Tools (`xcode-select --install`), macOS 13+.

```bash
./build.sh            # quit the app first when rebuilding
open StayAwake.app    # or: cp -R StayAwake.app /Applications/
```

If you move the app, toggle Launch at Login off and on once so the login item
follows the new path.

## Allow Closed Lid (optional)

Closed-lid mode runs `pmset disablesleep 1`, which needs root. Install a sudoers
rule that permits exactly `pmset disablesleep 0` and `pmset disablesleep 1`:

```bash
sudo scripts/install-lid-mode.sh            # install
sudo scripts/install-lid-mode.sh --remove   # remove and re-enable sleep
```

It only engages on AC power, releases within 30 s of unplugging, and a watchdog
re-enables sleep if the app dies. Manual escape hatch: `sudo pmset disablesleep 0`.

## Verify

```bash
pmset -g assertions | grep StayAwake   # during a session
pmset -g | grep SleepDisabled          # "1" while closed-lid mode is active
```
