#!/bin/bash
# Download and install munkitools (Munki package management system)
# GitHub: https://github.com/munki/munki
# Known good Team ID: T4SK8ZXCXG (Mac Admins Open Source)

set -e

# Known good signature values for verification
EXPECTED_TEAM_ID="T4SK8ZXCXG"
EXPECTED_ISSUER="Mac Admins Open Source"

INSTALL=false

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
    INSTALLED_VERSION=$(munkiimport --version 2>/dev/null | head -1 || echo "installed")
    echo "✓ munkitools is already installed"
    echo "  $INSTALLED_VERSION"
    exit 0
fi

echo "Checking for munkitools availability..."

# Get latest release from GitHub API
RELEASE_INFO=$(curl -s "https://api.github.com/repos/munki/munki/releases/latest" 2>/dev/null || echo "")

if [ -z "$RELEASE_INFO" ]; then
    echo "❌ Error: Could not fetch latest munkitools release from GitHub"
    echo "Please install munkitools manually from: https://github.com/munki/munki"
    exit 1
fi

# Extract download URL for the pkg installer
DOWNLOAD_URL=$(echo "$RELEASE_INFO" | grep -o "https://github.com/munki/munki/releases/download/[^\"]*\.pkg" | head -1)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "❌ Error: Could not find macOS .pkg installer for munkitools"
    echo "Please install munkitools manually from: https://github.com/munki/munki"
    exit 1
fi

RELEASE_TAG=$(echo "$RELEASE_INFO" | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
echo "Found munkitools release: $RELEASE_TAG"
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

# Verify package signature
echo "Verifying munkitools package signature..."
if command -v pkgutil &> /dev/null; then
    if pkgutil --check-signature "$TEMP_DIR/munkitools.pkg" &>/dev/null; then
        echo "✓ Package signature verified"
        
        # Extract and verify Team ID
        CERT_INFO=$(pkgutil --check-signature "$TEMP_DIR/munkitools.pkg" 2>&1)
        ACTUAL_TEAM_ID=$(echo "$CERT_INFO" | grep -oE "\(T[A-Z0-9]+\)" | head -1 | tr -d '()')
        ACTUAL_ISSUER=$(echo "$CERT_INFO" | grep "Developer ID Installer:" | head -1 | sed 's/.*Developer ID Installer: //' | sed 's/ (.*//')
        
        if [ "$ACTUAL_TEAM_ID" = "$EXPECTED_TEAM_ID" ]; then
            echo "✓ Team ID verified: $ACTUAL_TEAM_ID ($ACTUAL_ISSUER)"
        else
            echo "❌ ERROR: Team ID mismatch!"
            echo "   Expected: $EXPECTED_TEAM_ID ($EXPECTED_ISSUER)"
            echo "   Got: $ACTUAL_TEAM_ID ($ACTUAL_ISSUER)"
            exit 1
        fi
    else
        echo "❌ ERROR: Package signature verification failed"
        exit 1
    fi
else
    echo "⚠ pkgutil not available, skipping signature verification"
fi

echo "Installing munkitools (this requires sudo)..."
sudo installer -pkg "$TEMP_DIR/munkitools.pkg" -target /

# Verify installation
if command -v munkiimport &> /dev/null; then
    INSTALLED_VERSION=$(munkiimport --version 2>/dev/null | head -1 || echo "installed")
    echo "✓ munkitools installed successfully"
    echo "  $INSTALLED_VERSION"
else
    echo "❌ Error: munkitools installation verification failed"
    exit 1
fi
