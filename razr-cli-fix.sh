#!/bin/bash
# =============================================================================
# Motorola Razr — External Display (CLI) App Unlock Script
# =============================================================================
#
# Removes Motorola's restrictions on which apps can run on the external
# (cover/CLI) display. Works on Razr+ 2024, Razr 2024, and likely other
# Razr models with the CLI display.
#
# REQUIREMENTS:
#   - ADB installed on your computer (android-platform-tools)
#   - USB Debugging enabled on the phone
#   - Phone connected via USB or wireless ADB
#
# USAGE:
#   ./razr-cli-fix.sh              # Run full setup (run after every reboot)
#   ./razr-cli-fix.sh --check      # Verify current state
#   ./razr-cli-fix.sh --add PKG    # Whitelist a specific package
#   ./razr-cli-fix.sh --niagara    # Launch Niagara on external display
#   ./razr-cli-fix.sh --launcher PKG/ACTIVITY  # Launch any launcher on external display
#   ./razr-cli-fix.sh --help       # Show help
#
# =============================================================================

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }
log_header()  { echo -e "\n${BOLD}=== $1 ===${NC}\n"; }

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
check_adb() {
    if ! command -v adb &> /dev/null; then
        log_error "ADB not found. Install android-platform-tools first."
        echo "  Arch:    sudo pacman -S android-tools"
        echo "  Ubuntu:  sudo apt install adb"
        echo "  Fedora:  sudo dnf install android-tools"
        echo "  macOS:   brew install android-platform-tools"
        echo "  Windows: https://developer.android.com/tools/releases/platform-tools"
        exit 1
    fi
}

check_device() {
    local device_count
    device_count=$(adb devices 2>/dev/null | grep -c "device$" || true)
    if [ "$device_count" -eq 0 ]; then
        log_error "No device found. Make sure:"
        echo "  1. USB Debugging is enabled on the phone"
        echo "  2. Phone is connected via USB or wireless ADB"
        echo "  3. You've authorized the computer on the phone"
        exit 1
    fi
    local device_model
    device_model=$(adb shell getprop ro.product.model 2>/dev/null || echo "Unknown")
    log_success "Device connected: $device_model"
}

check_climanager() {
    if ! adb shell cmd climanager is-allow-all-oncli &> /dev/null; then
        log_error "climanager service not available."
        echo "  This script only works on Motorola Razr devices with an external CLI display."
        echo "  Check: adb shell service list | grep climanager"
        exit 1
    fi
    log_success "CLI Manager service available"
}

# ---------------------------------------------------------------------------
# Core functions
# ---------------------------------------------------------------------------

# Get the list of packages on the deny list (both user-set and pre-granted)
get_denied_packages() {
    adb shell cmd climanager list-pkgs-denied-oncli 2>/dev/null | while IFS= read -r line; do
        # Skip headers and section markers
        if echo "$line" | grep -q "Packages denied\|===\|Set by user:\|Pre granted:"; then
            continue
        fi
        local trimmed
        trimmed=$(echo "$line" | tr -d '[:space:]')
        if [ -n "$trimmed" ]; then
            echo "$trimmed"
        fi
    done
}

# Get the list of currently whitelisted packages
get_allowed_packages() {
    adb shell cmd climanager list-pkgs-allowed-oncli 2>/dev/null | while IFS= read -r line; do
        if echo "$line" | grep -q "Packages allowed\|===\|Set by user:\|Pre granted:"; then
            continue
        fi
        local trimmed
        trimmed=$(echo "$line" | tr -d '[:space:]')
        if [ -n "$trimmed" ]; then
            echo "$trimmed"
        fi
    done
}

# Detect the external display ID (the one that's ON and not display 0)
get_external_display_id() {
    local display_id
    display_id=$(adb shell dumpsys display 2>/dev/null | grep -A2 "Display Id=" | awk '
        /Display Id=/ { id=$0; gsub(/.*Display Id=/, "", id); gsub(/[^0-9]/, "", id) }
        /Display State=ON/ { if (id != "0") print id }
    ' | head -1)

    if [ -z "$display_id" ]; then
        echo "1"
    else
        echo "$display_id"
    fi
}

# ---------------------------------------------------------------------------
# Main actions
# ---------------------------------------------------------------------------
apply_fixes() {
    log_header "Motorola Razr — CLI Display App Unlock"

    local display_id
    display_id=$(get_external_display_id)
    log_info "External display ID: $display_id"

    # Step 1: Enable allow-all flag
    log_info "Setting global allow-all-on-CLI flag..."
    adb shell cmd climanager set-allow-all-oncli true 2>/dev/null
    log_success "Allow-all flag set"

    # Step 2: Auto-detect all denied packages and whitelist them
    log_info "Fetching denied packages list from device..."
    local denied_packages
    denied_packages=$(get_denied_packages)
    local denied_count
    denied_count=$(echo "$denied_packages" | grep -c "." || true)

    if [ "$denied_count" -gt 0 ]; then
        log_info "Found $denied_count denied packages. Whitelisting all..."
        echo "$denied_packages" | while IFS= read -r pkg; do
            if [ -n "$pkg" ]; then
                adb shell cmd climanager set-pkg-allowed-oncli "$pkg" true 2>/dev/null
                log_success "Allowed: $pkg"
            fi
        done
    else
        log_info "No denied packages found"
    fi

    # Step 3: Whitelist common system apps that may not appear on the deny
    #         list but can still be blocked
    log_info "Whitelisting common system apps..."
    local system_apps=(
        "com.android.settings"
        "com.android.dialer"
        "com.android.phone"
        "com.android.contacts"
        "com.android.vending"
        "com.android.chrome"
        "com.android.documentsui"
        "com.android.nfc"
        "com.android.printspooler"
        "com.android.intentresolver"
        "com.android.credentialmanager"
        "com.android.vpndialogs"
        "com.google.android.dialer"
        "com.google.android.contacts"
        "com.google.android.gm"
        "com.google.android.apps.maps"
        "com.google.android.apps.photos"
        "com.google.android.apps.docs"
        "com.google.android.apps.nbu.files"
        "com.google.android.apps.messaging"
        "com.google.android.apps.googleassistant"
        "com.google.android.apps.wellbeing"
        "com.google.android.calendar"
        "com.google.android.calculator"
        "com.google.android.deskclock"
        "com.google.android.keep"
        "com.google.android.youtube"
        "com.google.android.packageinstaller"
        "com.google.android.setupwizard"
        "com.google.android.cellbroadcastreceiver"
        "com.google.android.apps.podcasts"
    )
    for pkg in "${system_apps[@]}"; do
        if adb shell pm path "$pkg" &>/dev/null; then
            adb shell cmd climanager set-pkg-allowed-oncli "$pkg" true 2>/dev/null
            log_success "Allowed: $pkg"
        fi
    done

    # Step 4: Whitelist Settings component explicitly (needed on some firmware)
    adb shell cmd climanager set-cn-allowed-oncli com.android.settings/.Settings true 2>/dev/null
    log_success "Allowed component: com.android.settings/.Settings"

    # Step 5: Whitelist all user-installed apps (third-party apps)
    log_info "Whitelisting all user-installed apps..."
    local user_apps
    user_apps=$(adb shell pm list packages -3 2>/dev/null | sed 's/package://')
    local user_count
    user_count=$(echo "$user_apps" | grep -c "." || true)
    log_info "Found $user_count user-installed apps"
    echo "$user_apps" | while IFS= read -r pkg; do
        if [ -n "$pkg" ]; then
            adb shell cmd climanager set-pkg-allowed-oncli "$pkg" true 2>/dev/null
        fi
    done
    log_success "All user-installed apps whitelisted"

    echo ""
    log_success "All fixes applied!"
    echo ""
    log_warn "These settings reset on reboot. Run this script again after restarting."
}

verify_state() {
    log_header "Current CLI Manager State"

    # Device info
    local model codename android_ver
    model=$(adb shell getprop ro.product.model 2>/dev/null || echo "Unknown")
    codename=$(adb shell getprop ro.product.device 2>/dev/null || echo "Unknown")
    android_ver=$(adb shell getprop ro.build.version.release 2>/dev/null || echo "Unknown")
    echo "  Device:    $model ($codename)"
    echo "  Android:   $android_ver"
    echo ""

    # Display state
    log_info "Display state:"
    adb shell dumpsys display 2>/dev/null | grep -A3 "Display Id=" | grep -E "Display Id=|Display State=" | \
        sed 'N;s/\n/  /' | while read -r line; do
        echo "  $line"
    done
    echo ""

    # Allow-all flag
    local allow_all
    allow_all=$(adb shell cmd climanager is-allow-all-oncli 2>/dev/null)
    echo "  $allow_all"
    echo ""

    # Key packages check
    log_info "Checking key packages..."
    local key_packages=("com.android.settings" "com.android.dialer" "com.android.phone")
    local allowed_list
    allowed_list=$(get_allowed_packages)
    for pkg in "${key_packages[@]}"; do
        if echo "$allowed_list" | grep -q "^${pkg}$"; then
            log_success "$pkg is ALLOWED on CLI"
        else
            log_error "$pkg is NOT allowed on CLI"
        fi
    done
    echo ""

    # Summary
    local denied_count allowed_count
    denied_count=$(get_denied_packages | grep -c "." || true)
    allowed_count=$(echo "$allowed_list" | grep -c "." || true)
    log_info "Packages on deny list: $denied_count"
    log_info "Packages on allow list: $allowed_count"
    echo ""

    # Test launch
    local display_id
    display_id=$(get_external_display_id)
    log_info "Test launching Settings on display $display_id..."
    adb shell am start --display "$display_id" -n com.android.settings/.Settings 2>/dev/null
    log_info "Check your external display — Settings should be open"
}

launch_on_external() {
    local component="$1"
    local display_id
    display_id=$(get_external_display_id)
    log_info "Launching $component on display $display_id..."
    adb shell am start --display "$display_id" -n "$component" 2>/dev/null
    log_success "Launch command sent"
}

launch_niagara() {
    launch_on_external "bitpit.launcher/.ui.HomeActivity"
}

add_package() {
    local pkg="$1"
    if ! adb shell pm path "$pkg" &>/dev/null; then
        log_warn "Package $pkg does not appear to be installed, whitelisting anyway..."
    fi
    adb shell cmd climanager set-pkg-allowed-oncli "$pkg" true 2>/dev/null
    log_success "Added $pkg to CLI whitelist"
}

list_denied() {
    log_header "Packages Denied on CLI Display"
    adb shell cmd climanager list-pkgs-denied-oncli 2>/dev/null
}

list_allowed() {
    log_header "Packages Allowed on CLI Display"
    adb shell cmd climanager list-pkgs-allowed-oncli 2>/dev/null
}

generate_ondevice_script() {
    log_info "Generating on-device boot script..." >&2
    log_info "Fetching current deny list from device..." >&2

    local denied_packages
    denied_packages=$(get_denied_packages)

    cat <<'HEADER'
#!/system/bin/sh
# =============================================================================
# Motorola Razr — CLI Display Fix (On-Device Boot Script)
# =============================================================================
# Auto-generated by razr-cli-fix.sh
#
# Installation (requires root):
#   1. Copy to /data/adb/service.d/fix-cli.sh
#   2. chmod +x /data/adb/service.d/fix-cli.sh
#   3. Reboot
# =============================================================================

# Wait for system services to be ready
sleep 15

# Enable global allow-all flag
cmd climanager set-allow-all-oncli true

HEADER

    echo "# Whitelist all packages from the deny list"
    echo "$denied_packages" | while IFS= read -r pkg; do
        if [ -n "$pkg" ]; then
            echo "cmd climanager set-pkg-allowed-oncli $pkg true"
        fi
    done

    cat <<'FOOTER'

# Whitelist common system apps
cmd climanager set-pkg-allowed-oncli com.android.settings true
cmd climanager set-cn-allowed-oncli com.android.settings/.Settings true
cmd climanager set-pkg-allowed-oncli com.android.dialer true
cmd climanager set-pkg-allowed-oncli com.android.phone true
cmd climanager set-pkg-allowed-oncli com.android.contacts true
cmd climanager set-pkg-allowed-oncli com.android.vending true
cmd climanager set-pkg-allowed-oncli com.android.chrome true
cmd climanager set-pkg-allowed-oncli com.google.android.dialer true
cmd climanager set-pkg-allowed-oncli com.google.android.contacts true
cmd climanager set-pkg-allowed-oncli com.google.android.apps.nbu.files true
cmd climanager set-pkg-allowed-oncli com.google.android.apps.googleassistant true
cmd climanager set-pkg-allowed-oncli com.google.android.apps.maps true
cmd climanager set-pkg-allowed-oncli com.google.android.apps.photos true
cmd climanager set-pkg-allowed-oncli com.google.android.apps.messaging true

# Whitelist all user-installed (third-party) apps
for pkg in $(pm list packages -3 | sed 's/package://'); do
    cmd climanager set-pkg-allowed-oncli "$pkg" true
done
FOOTER

    log_success "Boot script generated. Redirect to a file:" >&2
    echo "  $0 --gen-boot-script > fix-cli.sh" >&2
}

show_help() {
    echo -e "${BOLD}Motorola Razr — External Display (CLI) App Unlock${NC}"
    echo ""
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  (none)              Apply all fixes (run after every reboot)"
    echo "  --check             Verify current state without changing anything"
    echo "  --add PKG           Whitelist a specific package"
    echo "  --niagara           Launch Niagara Launcher on external display"
    echo "  --launcher CMP      Launch any app on external display (package/activity)"
    echo "  --list-denied       Show all packages on the deny list"
    echo "  --list-allowed      Show all packages on the allow list"
    echo "  --gen-boot-script   Generate a root boot script for on-device automation"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                                # Fix everything"
    echo "  $0 --add com.spotify.music                        # Allow Spotify on CLI"
    echo "  $0 --launcher bitpit.launcher/.ui.HomeActivity    # Launch Niagara"
    echo "  $0 --gen-boot-script > fix-cli.sh                 # Save boot script"
    echo ""
    echo "Note: Fixes reset on reboot. Run this script after every restart."
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
check_adb
check_device
check_climanager

case "${1:-}" in
    --check)
        verify_state
        ;;
    --add)
        if [ -z "${2:-}" ]; then
            log_error "Usage: $0 --add <package.name>"
            echo "  Find package names with: adb shell pm list packages | grep <keyword>"
            exit 1
        fi
        add_package "$2"
        ;;
    --niagara)
        launch_niagara
        ;;
    --launcher)
        if [ -z "${2:-}" ]; then
            log_error "Usage: $0 --launcher <package/activity>"
            echo "  Example: $0 --launcher bitpit.launcher/.ui.HomeActivity"
            echo "  Find activity: adb shell cmd package resolve-activity -c android.intent.category.HOME <package>"
            exit 1
        fi
        launch_on_external "$2"
        ;;
    --list-denied)
        list_denied
        ;;
    --list-allowed)
        list_allowed
        ;;
    --gen-boot-script)
        generate_ondevice_script
        ;;
    --help|-h)
        show_help
        ;;
    *)
        apply_fixes
        verify_state
        ;;
esac
