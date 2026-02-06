#!/bin/bash
set -e

# =============================================================================
# barcc Build & Distribution Script
# =============================================================================

# Configuration - set these environment variables or edit here
APPLE_ID="${APPLE_ID:-}"                    # Your Apple ID email
TEAM_ID="${TEAM_ID:-}"                      # Your Team ID (find in developer portal)
APP_PASSWORD="${APP_PASSWORD:-}"            # App-specific password from appleid.apple.com
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"    # "Developer ID Application: Name (TEAM_ID)"

# App metadata
APP_NAME="barcc"
BUNDLE_ID="com.barcc.app"
VERSION="${VERSION:-1.0}"

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Build Functions
# =============================================================================

build_binary() {
    log_info "Building release binary..."
    cd "$PROJECT_DIR"
    swift build -c release
    log_info "Build complete: $BUILD_DIR/barcc"
}

create_app_bundle() {
    log_info "Creating app bundle..."

    # Clean and create directories
    rm -rf "$DIST_DIR"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"

    # Copy binary
    cp "$BUILD_DIR/barcc" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

    # Copy Info.plist
    cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"

    # Copy app icon
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

    # Create PkgInfo
    echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

    log_info "App bundle created: $APP_BUNDLE"
}

sign_app() {
    if [ -z "$SIGNING_IDENTITY" ]; then
        log_warn "No SIGNING_IDENTITY set - skipping code signing"
        log_warn "Users will need to right-click → Open on first launch"
        return 0
    fi

    log_info "Code signing app bundle..."

    codesign --deep --force --verify --verbose \
        --options runtime \
        --sign "$SIGNING_IDENTITY" \
        "$APP_BUNDLE"

    # Verify signature
    codesign --verify --verbose "$APP_BUNDLE"
    log_info "Code signing complete"
}

notarize_app() {
    if [ -z "$APPLE_ID" ] || [ -z "$TEAM_ID" ] || [ -z "$APP_PASSWORD" ]; then
        log_warn "Missing notarization credentials - skipping notarization"
        log_warn "Set APPLE_ID, TEAM_ID, and APP_PASSWORD environment variables"
        return 0
    fi

    log_info "Creating ZIP for notarization..."
    cd "$DIST_DIR"
    zip -r "$APP_NAME.zip" "$APP_NAME.app"

    log_info "Submitting for notarization (this may take a few minutes)..."
    xcrun notarytool submit "$APP_NAME.zip" \
        --apple-id "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait

    log_info "Stapling notarization ticket..."
    xcrun stapler staple "$APP_BUNDLE"

    # Clean up zip
    rm "$APP_NAME.zip"

    log_info "Notarization complete"
}

create_dmg() {
    log_info "Creating DMG..."

    DMG_PATH="$DIST_DIR/$DMG_NAME"
    rm -f "$DMG_PATH"

    # Create temporary DMG directory with Applications symlink
    DMG_TEMP="$DIST_DIR/dmg-temp"
    rm -rf "$DMG_TEMP"
    mkdir -p "$DMG_TEMP"
    cp -R "$APP_BUNDLE" "$DMG_TEMP/"
    ln -s /Applications "$DMG_TEMP/Applications"

    # Remove quarantine attribute to prevent "damaged" error on other Macs
    xattr -cr "$DMG_TEMP/$APP_NAME.app"

    # Create DMG
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_TEMP" \
        -ov -format UDZO \
        "$DMG_PATH"

    # Clean up
    rm -rf "$DMG_TEMP"

    log_info "DMG created: $DMG_PATH"
}

# =============================================================================
# Main
# =============================================================================

usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  all        Build, sign, notarize, and create DMG (default)"
    echo "  build      Build release binary only"
    echo "  bundle     Create app bundle (runs build first)"
    echo "  sign       Sign app bundle"
    echo "  notarize   Notarize app bundle"
    echo "  dmg        Create DMG"
    echo "  unsigned   Build + bundle + DMG without signing (for testing)"
    echo ""
    echo "Environment variables for signing/notarization:"
    echo "  SIGNING_IDENTITY  - Developer ID Application: Your Name (TEAM_ID)"
    echo "  APPLE_ID          - Your Apple ID email"
    echo "  TEAM_ID           - Your Apple Developer Team ID"
    echo "  APP_PASSWORD      - App-specific password from appleid.apple.com"
}

main() {
    local cmd="${1:-all}"

    case "$cmd" in
        build)
            build_binary
            ;;
        bundle)
            build_binary
            create_app_bundle
            ;;
        sign)
            sign_app
            ;;
        notarize)
            notarize_app
            ;;
        dmg)
            create_dmg
            ;;
        unsigned)
            build_binary
            create_app_bundle
            create_dmg
            log_info "Unsigned build complete!"
            log_info "App: $APP_BUNDLE"
            log_info "DMG: $DIST_DIR/$DMG_NAME"
            ;;
        all)
            build_binary
            create_app_bundle
            sign_app
            notarize_app
            create_dmg
            log_info "Build complete!"
            log_info "App: $APP_BUNDLE"
            log_info "DMG: $DIST_DIR/$DMG_NAME"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            log_error "Unknown command: $cmd"
            usage
            exit 1
            ;;
    esac
}

main "$@"
