#!/bin/bash
# ─────────────────────────────────────────────
#  build-hanamimi.sh — Hanamimi local release build
#
#  Usage:
#    ./build-hanamimi.sh            → full build + install + launch
#    ./build-hanamimi.sh --install  → skip build, just install + launch
#    ./build-hanamimi.sh --help     → show this help
# ─────────────────────────────────────────────

set -euo pipefail

# ── Colours ──────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

run() {
    echo -e "${YELLOW}  Running Command :${RESET} ${BOLD}$*${RESET}"
    "$@"
}

usage() {
    echo -e "${BOLD}Usage:${RESET}"
    echo -e "  build-hanamimi             Full build → install → launch"
    echo -e "  build-hanamimi --install   Skip build, just install + launch existing APK"
    echo -e "  build-hanamimi --help      Show this help"
    exit 0
}

# ── Parse args ───────────────────────────────
MODE="full"
for arg in "$@"; do
    case "$arg" in
        --install) MODE="install" ;;
        --help|-h) usage ;;
        *) die "Unknown argument: $arg. Run with --help for usage." ;;
    esac
done

# ── Config ───────────────────────────────────
PROJECT_DIR="/home/sappy/projects/hanamimi"
KEYSTORE_PATH="$PROJECT_DIR/android/keystore/sappy-release.jks"
KEY_PROPERTIES="$PROJECT_DIR/android/key.properties"
APP_PACKAGE="com.hanamimi.app"
APK_PATH="$PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"

# ─────────────────────────────────────────────
echo ""
if [[ "$MODE" == "install" ]]; then
    echo -e "${BOLD}${CYAN}▶ Mode: Install + Launch only${RESET}"
else
    echo -e "${BOLD}${CYAN}▶ Mode: Full Build + Install + Launch${RESET}"
fi
echo ""

# ── 1. ADB device check ──────────────────────
info "Checking for connected ADB devices..."
adb start-server &>/dev/null

DEVICE_COUNT=$(adb devices | grep -c "device$" || true)
if [[ "$DEVICE_COUNT" -eq 0 ]]; then
    die "No ADB devices found. Connect a device and try again."
fi
success "Found $DEVICE_COUNT device(s):"
adb devices | grep "device$" | awk '{print "         → " $1}'

# Wireless debugging often lists the same phone twice (mDNS) —
# target the first entry explicitly. Serials can contain spaces
# ("host (2)._adb-tls…"), so split on the tab, not whitespace.
DEVICE=$(adb devices | grep -P '\tdevice$' | head -1 | cut -f1)
ADB=(adb -s "$DEVICE")
info "Using device: $DEVICE"

# ── 2. Project dir check ─────────────────────
[[ -d "$PROJECT_DIR" ]] || die "Project directory not found: $PROJECT_DIR"
cd "$PROJECT_DIR"
success "Working directory: $PROJECT_DIR"

# ═════════════════════════════════════════════
#  INSTALL-ONLY MODE
# ═════════════════════════════════════════════
if [[ "$MODE" == "install" ]]; then
    [[ -f "$APK_PATH" ]] || die "No APK found at $APK_PATH — run a full build first."
    APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
    info "Found APK (${APK_SIZE}) — installing..."
    if ! run "${ADB[@]}" install -r "$APK_PATH"; then
        warn "Install failed — likely a debug↔release signature mismatch."
        warn "Uninstalling old build (app data will be reset) and retrying..."
        run "${ADB[@]}" uninstall "$APP_PACKAGE" || true
        run "${ADB[@]}" install "$APK_PATH"
    fi
    success "APK installed."

    info "Launching $APP_PACKAGE..."
    run "${ADB[@]}" shell monkey -p "$APP_PACKAGE" -c android.intent.category.LAUNCHER 1
    success "App launched!"

    echo ""
    echo -e "${BOLD}${GREEN}✓ Install → Launch complete!${RESET}"
    echo -e "  Package : ${CYAN}$APP_PACKAGE${RESET}"
    echo -e "  APK     : ${CYAN}$APK_PATH${RESET} (${APK_SIZE})"
    exit 0
fi

# ═════════════════════════════════════════════
#  FULL BUILD MODE
# ═════════════════════════════════════════════

# ── 3. Keystore check ────────────────────────
[[ -f "$KEYSTORE_PATH" ]]   || die "Keystore not found at $KEYSTORE_PATH"
[[ -f "$KEY_PROPERTIES" ]]  || die "key.properties not found at $KEY_PROPERTIES"
success "Keystore + key.properties found (signing handled by Gradle)."

# ── 4. Analyze + tests ───────────────────────
info "Running flutter analyze..."
run flutter analyze
success "Analyze clean."

info "Running tests..."
run flutter test
success "Tests passed."

# ── 5. Release build ─────────────────────────
BUILD_START=$(date +%s)
info "Building signed release APK..."
run flutter build apk --release
BUILD_END=$(date +%s)
BUILD_TIME=$(( BUILD_END - BUILD_START ))
success "Build complete in ${BUILD_TIME}s."

# ── 6. APK sanity check ──────────────────────
[[ -f "$APK_PATH" ]] || die "APK not found at expected path: $APK_PATH"
APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
success "APK ready — size: $APK_SIZE  →  $APK_PATH"

# ── 7. Install ───────────────────────────────
info "Installing APK on device(s)..."
if ! run "${ADB[@]}" install -r "$APK_PATH"; then
    warn "Install failed — likely a debug↔release signature mismatch."
    warn "Uninstalling old build (app data will be reset) and retrying..."
    run "${ADB[@]}" uninstall "$APP_PACKAGE" || true
    run "${ADB[@]}" install "$APK_PATH"
fi
success "APK installed."

# ── 8. Launch ────────────────────────────────
info "Launching $APP_PACKAGE..."
run "${ADB[@]}" shell monkey -p "$APP_PACKAGE" -c android.intent.category.LAUNCHER 1
success "App launched!"

echo ""
echo -e "${BOLD}${GREEN}✓ Build → Install → Launch complete!${RESET}"
echo -e "  Package : ${CYAN}$APP_PACKAGE${RESET}"
echo -e "  APK     : ${CYAN}$APK_PATH${RESET} (${APK_SIZE})"
echo -e "  Time    : ${CYAN}${BUILD_TIME}s${RESET}"
