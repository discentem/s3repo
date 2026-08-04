#!/bin/bash
# Download and install munkitools (Munki package management system)
# GitHub: https://github.com/munki/munki
# Pinned to: v7.2.0.5787 package
# Signed by: Team ID T4SK8ZXCXG (Mac Admins Open Source)

set -e

# Pinned release with SHA256 hash for verification
MUNKITOOLS_VERSION="v7.2.0.5787"
MUNKITOOLS_PKG_SHA256="0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5"
EXPECTED_TEAM_ID="T4SK8ZXCXG"
EXPECTED_ISSUER="Mac Admins Open Source"

INSTALL=false

# Verify munkitools package signature and Team ID
verify_munkitools_package() {
    local pkg_path="$1"
    
    if [ ! -f "$pkg_path" ]; then
        echo "❌ Error: munkitools package not found at $pkg_path"
        return 1
    fi
    
    echo "Verifying munkitools package signature..."
    if command -v pkgutil &> /dev/null; then
        if pkgutil --check-signature "$pkg_path" &>/dev/null; then
            echo "✓ Package signature verified"
            
            # Extract and verify Team ID
            CERT_INFO=$(pkgutil --check-signature "$pkg_path" 2>&1)
            ACTUAL_TEAM_ID=$(echo "$CERT_INFO" | grep -oE "\(T[A-Z0-9]+\)" | head -1 | tr -d '()')
            ACTUAL_ISSUER=$(echo "$CERT_INFO" | grep "Developer ID Installer:" | head -1 | sed 's/.*Developer ID Installer: //' | sed 's/ (.*//')
            
            if [ "$ACTUAL_TEAM_ID" = "$EXPECTED_TEAM_ID" ]; then
                echo "✓ Team ID verified: $ACTUAL_TEAM_ID ($ACTUAL_ISSUER)"
                return 0
            else
                echo "❌ ERROR: Team ID mismatch!"
                echo "   Expected: $EXPECTED_TEAM_ID ($EXPECTED_ISSUER)"
                echo "   Got: $ACTUAL_TEAM_ID ($ACTUAL_ISSUER)"
                return 1
            fi
        else
            echo "❌ ERROR: Package signature verification failed"
            return 1
        fi
    else
        echo "❌ ERROR: pkgutil is not available. Cannot verify package signature and Team ID."
        echo "   pkgutil is required to verify munkitools authenticity."
        return 1
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --install)
            INSTALL=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --install         Download and install munkitools"
            echo "  --help            Show this help message"
            echo ""
            echo "Note: munkitools installation requires sudo and will install system-wide"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if munkitools is already installed
if command -v munkiimport &> /dev/null; then
    MUNKIIMPORT_BIN=$(command -v munkiimport)
    echo "Found munkiimport at: $MUNKIIMPORT_BIN"
    
    # Verify the installed binary has code signing
    echo "Verifying munkiimport binary code signing..."
    if codesign -v -strict "$MUNKIIMPORT_BIN" &>/dev/null; then
        INSTALLED_VERSION=$(munkiimport --version 2>/dev/null | head -1 || echo "installed")
        echo "✓ munkitools is already installed and verified"
        echo "  $INSTALLED_VERSION"
        exit 0
    else
        echo "⚠ munkiimport binary does not have valid code signing"
        echo "  Reinstalling to ensure proper verification..."
    fi
fi

echo "Checking for munkitools availability..."

# Use pinned release version
DOWNLOAD_URL="https://github.com/munki/munki/releases/download/${MUNKITOOLS_VERSION}/munkitools-${MUNKITOOLS_VERSION}.pkg"

echo "Found munkitools release: $MUNKITOOLS_VERSION"
echo "Download URL: $DOWNLOAD_URL"

if [ "$INSTALL" = false ]; then
    echo ""
    echo "To install munkitools, run:"
    echo "  $0 --install"
    exit 0
fi

# Create temporary directory for download
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Downloading munkitools..."
curl -L -o "$TEMP_DIR/munkitools.pkg" "$DOWNLOAD_URL"

if [ ! -f "$TEMP_DIR/munkitools.pkg" ]; then
    echo "❌ Error: Failed to download munkitools"
    exit 1
fi

echo "Verifying download integrity..."
DOWNLOADED_SHA=$(sha256sum "$TEMP_DIR/munkitools.pkg" | awk '{print $1}')
if [ "$DOWNLOADED_SHA" != "$MUNKITOOLS_PKG_SHA256" ]; then
    echo "❌ ERROR: Downloaded file SHA256 does not match pinned hash"
    echo "   Downloaded: $DOWNLOADED_SHA"
    echo "   Expected:   $MUNKITOOLS_PKG_SHA256"
    exit 1
fi
echo "✓ Download integrity verified"

# Verify package signature and Team ID
if ! verify_munkitools_package "$TEMP_DIR/munkitools.pkg"; then
    exit 1
fi

echo "Installing munkitools (this requires sudo)..."
sudo installer -pkg "$TEMP_DIR/munkitools.pkg" -target /

# Verify installation
if command -v munkiimport &> /dev/null; then
    MUNKIIMPORT_BIN=$(command -v munkiimport)
    echo "Verifying installed munkiimport binary code signing..."
    if codesign -v -strict "$MUNKIIMPORT_BIN" &>/dev/null; then
        INSTALLED_VERSION=$(munkiimport --version 2>/dev/null | head -1 || echo "installed")
        echo "✓ munkitools installed successfully and verified"
        echo "  $INSTALLED_VERSION"
    else
        echo "⚠ munkiimport installed but binary does not have valid code signing"
    fi
else
    echo "❌ Error: munkitools installation verification failed"
    exit 1
fi
