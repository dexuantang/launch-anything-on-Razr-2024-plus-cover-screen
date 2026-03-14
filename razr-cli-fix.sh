#!/bin/bash
# =============================================================================
# Motorola Razr+ 2024 — External Display (CLI) App Unlock Script
# =============================================================================
#
# This script removes Motorola's restrictions on which apps can run on the
# external (cover/CLI) display. Useful when the inner screen is broken or
# if you simply prefer using the external screen full-time.
#
# REQUIREMENTS:
#   - ADB installed on your computer (android-platform-tools)
#   - USB Debugging enabled on the phone
#   - Phone connected via USB or wireless ADB
#
# USAGE:
#   ./razr-cli-fix.sh          # Run full setup (first time)
#   ./razr-cli-fix.sh --check  # Verify current state
#   ./razr-cli-fix.sh --reboot # Apply fixes and reboot to verify persistence
#
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Packages on Motorola's pre-granted deny list (hardcoded in firmware).
# These CANNOT be removed from the deny list, but CAN be overridden by
# adding them to the allow list with set-pkg-allowed-oncli.
# ---------------------------------------------------------------------------
DENIED_PACKAGES=(
    "com.android.dialer"
    "com.android.phone"
    "com.android.settings"
    "com.motorola.cli.settings"
    "com.motorola.dolby.dolbyui"
    "com.motorola.securityhub"
    "com.motorola.launcher3"
    "com.motorola.personalize"
    "com.motorola.cn.lrhealth"
    "com.motorola.cn.wallet"
    "com.motorola.cn.devicemigration"
    "com.motorola.cn.voicetranslation"
    "com.google.android.apps.googleassistant"
    "com.google.android.apps.nbu.files"
    "com.google.android.apps.podcasts"
    "com.google.android.setupwizard"
    "com.google.android.cellbroadcastreceiver"
    "com.lenovo.motorola.argus.camera"
    "com.lenovoimage.MotoZXPrint"
    "com.zui.zhealthy"
)

# ---------------------------------------------------------------------------
# Additional components that need explicit component-level whitelisting
# ---------------------------------------------------------------------------
ALLOWED_COMPONENTS=(
    "com.android.settings/.Settings"
)

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }

check_adb() {
    if ! command -v adb &> /dev/null; then
        log_error "ADB not found. Install android-platform-tools first."
        echo "  Arch:   sudo pacman -S android-tools"
        echo "  Ubuntu: sudo apt install adb"
        echo "  macOS:  brew install android-platform-tools"
        exit 1
    fi
}

check_device() {
    local device_count
    device_count=$(adb devices | grep -c "device$" || true)
    if [ "$device_count" -eq 0 ]; then
        log_error "No device found. Make sure:"
        echo "  1. USB Debugging is enabled on the phone"
        echo "  2. Phone is connected via USB or wireless ADB"
        echo "  3. You've authorized the computer on the phone"
        exit 1
    fi
    log_success "Device connected"
}

check_climanager() {
    if ! adb shell cmd climanager is-allow-all-oncli &> /dev/null; then
        log_error "climanager service not available. Is this a Motorola Razr?"
        exit 1
    fi
    log_success "CLI Manager service available"
}

# ---------------------------------------------------------------------------
# Main actions
# ---------------------------------------------------------------------------
apply_fixes() {
    log_info "=== Motorola Razr+ 2024 CLI Display Fix ==="
    echo ""

    # Step 1: Enable allow-all flag
    log_info "Setting allow-all-oncli flag..."
    adb shell cmd climanager set-allow-all-oncli true
    log_success "Allow-all flag set"

    # Step 2: Whitelist all denied packages
    log_info "Whitelisting denied packages..."
    for pkg in "${DENIED_PACKAGES[@]}"; do
        adb shell cmd climanager set-pkg-allowed-oncli "$pkg" true 2>/dev/null && \
            log_success "Allowed: $pkg" || \
            log_warn "Skipped: $pkg (may not be installed)"
    done

    # Step 3: Whitelist specific components
    log_info "Whitelisting specific components..."
    for cn in "${ALLOWED_COMPONENTS[@]}"; do
        adb shell cmd climanager set-cn-allowed-oncli "$cn" true 2>/dev/null && \
            log_success "Allowed component: $cn" || \
            log_warn "Skipped component: $cn"
    done

    echo ""
    log_success "=== All fixes applied ==="
    echo ""
}

launch_niagara() {
    log_info "Launching Niagara Launcher on external display..."
    adb shell am start --display 1 -n bitpit.launcher/.ui.HomeActivity 2>/dev/null && \
        log_success "Niagara launched on display 1" || \
        log_warn "Niagara not installed or failed to launch"
}

verify_state() {
    echo ""
    log_info "=== Current CLI Manager State ==="
    echo ""

    # Check allow-all flag
    local allow_all
    allow_all=$(adb shell cmd climanager is-allow-all-oncli 2>/dev/null)
    echo "  $allow_all"
    echo ""

    # Check if key packages are allowed
    log_info "Checking key packages..."
    for pkg in "com.android.settings" "com.android.dialer" "com.android.phone" "com.motorola.cli.settings"; do
        if adb shell cmd climanager list-pkgs-allowed-oncli 2>/dev/null | grep -q "$pkg"; then
            log_success "$pkg is ALLOWED"
        else
            log_error "$pkg is NOT allowed"
        fi
    done
    echo ""

    # Check deny list
    log_info "Packages still on deny list:"
    adb shell cmd climanager list-pkgs-denied-oncli 2>/dev/null | head -20
    echo ""

    # Test launch
    log_info "Test launching Settings on display 1..."
    adb shell am start --display 1 -n com.android.settings/.Settings 2>/dev/null
    log_info "Check your external display — Settings should be open"
}

show_help() {
    echo "Motorola Razr+ 2024 — External Display Fix"
    echo ""
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  (none)     Apply all fixes (run after every reboot)"
    echo "  --check    Verify current state without changing anything"
    echo "  --reboot   Apply fixes, reboot, and remind to re-run"
    echo "  --niagara  Launch Niagara on the external display"
    echo "  --add PKG  Add a specific package to the CLI whitelist"
    echo "  --help     Show this help message"
    echo ""
    echo "Note: The allow-all flag and user-set whitelist entries reset on"
    echo "reboot. Run this script after every reboot, or set up automation"
    echo "on the phone (e.g., Tasker + Shizuku, or Termux:Boot with root)."
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
    --reboot)
        apply_fixes
        log_info "Rebooting device..."
        adb reboot
        echo ""
        log_warn "After phone boots, run this script again:"
        echo "  ./razr-cli-fix.sh"
        ;;
    --niagara)
        launch_niagara
        ;;
    --add)
        if [ -z "${2:-}" ]; then
            log_error "Usage: $0 --add <package.name>"
            exit 1
        fi
        adb shell cmd climanager set-pkg-allowed-oncli "$2" true
        log_success "Added $2 to CLI whitelist"
        ;;
    --help|-h)
        show_help
        ;;
    *)
        apply_fixes
        launch_niagara
        verify_state
        ;;
esac
