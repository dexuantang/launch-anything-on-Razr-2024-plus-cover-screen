# Motorola Razr+ 2024 — External Display App Unlock

Force **any** Android app to run on the Motorola Razr+ 2024 external (cover/CLI) display, bypassing Motorola's built-in restrictions.

## The Problem

Motorola's stock firmware blocks many apps from launching on the external display. When you try to open them, you get a **"Flip open to continue"** toast message. This is enforced at the framework level by Motorola's custom `CliManagerService` inside `system_server` — not just the launcher.

This is especially painful if your **inner screen is broken**, since the phone becomes nearly unusable for anything beyond the apps Motorola pre-approved.

## The Solution

Motorola ships a hidden shell service called `climanager` with commands to manage app access on the CLI (Cover Lid Interface) display. This script uses those commands to:

1. Set a global "allow all apps on CLI" flag
2. Individually whitelist every package on Motorola's hardcoded deny list
3. Optionally launch a third-party launcher (Niagara) on the external display

**No root required.** Just ADB access from a computer.

## Requirements

- **Computer** with ADB installed:
  - Arch Linux: `sudo pacman -S android-tools`
  - Ubuntu/Debian: `sudo apt install adb`
  - macOS: `brew install android-platform-tools`
  - Windows: [Download Platform Tools](https://developer.android.com/tools/releases/platform-tools)
- **USB cable** connecting your phone to the computer
- **USB Debugging** enabled on the phone:
  - Go to `Settings > About Phone` and tap `Build Number` 7 times to enable Developer Options
  - Go to `Settings > System > Developer Options` and enable `USB Debugging`
  - If your inner screen is broken, you'll need to do this via the external display (if accessible) or have it pre-enabled

## Quick Start

```bash
git clone https://github.com/YOUR_USERNAME/razr-cli-fix.git
cd razr-cli-fix
chmod +x razr-cli-fix.sh
./razr-cli-fix.sh
```

## Usage

```bash
# Apply all fixes (run this after every reboot)
./razr-cli-fix.sh

# Check current state without changing anything
./razr-cli-fix.sh --check

# Whitelist a specific app that's getting blocked
./razr-cli-fix.sh --add com.example.someapp

# Launch Niagara Launcher on the external display
./razr-cli-fix.sh --niagara

# Apply fixes and reboot to test
./razr-cli-fix.sh --reboot

# Show help
./razr-cli-fix.sh --help
```

## Important: Fixes Reset on Reboot

The `set-allow-all-oncli` flag and user-set whitelist entries **do not persist** across reboots. You need to re-run the script after every reboot.


## How It Works

### Background

Motorola's Razr series uses a custom system service called `CliManagerService` (CLI = Cover Lid Interface) to control which apps can run on the external display. This service is baked into `system_server` via a patched `services.jar` at `/system/framework/services.jar`.

When any app tries to launch on the external display, the framework calls `isAllowedOnCLI()` which checks:

1. A **per-package whitelist** (allowed on CLI)
2. A **per-package deny list** (blocked from CLI)  
3. A **global allow-all flag**
4. A **hardcoded pre-granted deny list** (cannot be removed, only overridden by the whitelist)

The deny list takes priority over the allow-all flag, which is why simply setting `set-allow-all-oncli true` isn't enough — you also need to explicitly whitelist packages that are on the hardcoded deny list.

### Key Discovery

The `climanager` service exposes shell commands that are undocumented but fully functional:

| Command | Description |
|---------|-------------|
| `cmd climanager set-allow-all-oncli true` | Global flag to allow all apps |
| `cmd climanager set-pkg-allowed-oncli <pkg> true` | Whitelist a package (overrides deny list) |
| `cmd climanager set-cn-allowed-oncli <component> true` | Whitelist a specific activity |
| `cmd climanager set-pkg-denied-oncli <pkg> true/false` | Add/remove from user deny list |
| `cmd climanager list-pkgs-allowed-oncli` | Show all whitelisted packages |
| `cmd climanager list-pkgs-denied-oncli` | Show all denied packages |
| `cmd climanager is-allow-all-oncli` | Check global allow-all flag |

### Pre-Granted Deny List

These packages are hardcoded in Motorola's firmware and **cannot be removed** from the deny list. They must be overridden by adding them to the allow list:

```
com.android.dialer
com.android.phone
com.google.android.apps.googleassistant
com.google.android.apps.nbu.files
com.google.android.apps.podcasts
com.google.android.cellbroadcastreceiver
com.google.android.setupwizard
com.lenovo.motorola.argus.camera
com.lenovoimage.MotoZXPrint
com.motorola.cli.settings
com.motorola.cn.devicemigration
com.motorola.cn.lrhealth
com.motorola.cn.voicetranslation
com.motorola.cn.wallet
com.motorola.dolby.dolbyui
com.motorola.launcher3
com.motorola.personalize
com.motorola.securityhub
com.zui.zhealthy
```

## Using a Third-Party Launcher

You can launch [Niagara Launcher](https://play.google.com/store/apps/details?id=bitpit.launcher) (or any launcher) on the external display:

```bash
# Find the correct activity name for your launcher
adb shell cmd package resolve-activity -c android.intent.category.HOME <package.name>

# Launch it on the external display
adb shell am start --display 1 -n <package.name>/<activity.name>

# Example for Niagara:
adb shell am start --display 1 -n bitpit.launcher/.ui.HomeActivity
```

### Limitation: Home Button

The physical/gesture home button will still return to Motorola's built-in cover screen launcher. This is because Android uses the `SECONDARY_HOME` intent category for secondary displays, and Motorola's `SecondaryDisplayLauncher` is the only app registered for it. Changing this requires root access to hide or disable `com.motorola.launcher.secondarydisplay`.

You can set Niagara as the default home app for the primary display:

```bash
adb shell cmd package set-home-activity bitpit.launcher/.ui.HomeActivity
```

But this won't affect the external display's home behavior.



## Technical Details

### Relevant System Components

| Component | Path | Purpose |
|-----------|------|---------|
| CliManagerService | `/system/framework/services.jar` | Framework service enforcing CLI app restrictions |
| CLIManager | `/system/framework/moto-core_services.jar` | Client-side API for CLI management |
| ExternalDisplayLauncher | `/system_ext/priv-app/ExternalDisplayLauncher/` | Motorola's cover screen launcher |
| Launcher overlay | `/product/overlay/ExternalDisplayLauncherOverlayArcfox.apk` | Device-specific launcher config |

### Display IDs

- **Display 0**: Inner foldable display (primary)
- **Display 1**: External cover display (CLI)

### CLI Access Return Values

From `CLIManager.cliAccessToString()`:

| Value | Meaning |
|-------|---------|
| 0 | ALLOWED |
| 1 | IGNORED |
| 2 | DEFAULT (uses deny/allow list logic) |

## Disclaimer

This entire project was **vibe coded** — discovered through a live debugging session with Claude (Anthropic), reverse engineering Motorola's `CliManagerService` and `CliManagerShellCommand` classes via JADX decompilation of `services.jar` and `ExternalDisplayLauncher.apk`. No prior documentation for the `climanager` shell commands existed; we found them by pulling system JARs off the phone and decompiling them until we hit the right class. Therefore this may not work with other Razr models and there may be bugs.

