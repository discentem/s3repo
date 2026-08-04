#!/bin/bash
# Download and verify swiftpkg release from GitHub
# GitHub: https://github.com/codecarton/swiftpkg
# Pinned to: 0.1.1 (signed by Team ID DPXY7JLK67)

set -e

REPO="codecarton/swiftpkg"
SWIFTPKG_VERSION="0.1.1"
EXPECTED_TEAM_ID="DPXY7JLK67"
EXPECTED_ISSUER="codecarton"
DOWNLOAD_DIR="/tmp"
INSTALL=false

# Verify swiftpkg package signature and Team ID
verify_swiftpkg_package() {
    local pkg_path="$1"
    
    if [ ! -f "$pkg_path" ]; then
        echo "❌ Error: swiftpkg package not found at $pkg_path"
        return 1
    fi
    
    echo "Verifying swiftpkg package signature..."
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
        echo "   pkgutil is required to verify swiftpkg authenticity."
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
        --dir)
            DOWNLOAD_DIR="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dir DIR         Download directory (default: current directory)"
            echo "  --install         Install after verification"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Create download directory
mkdir -p "$DOWNLOAD_DIR"

echo "Fetching latest swiftpkg release from GitHub..."

# Get latest release info from GitHub API
RELEASE_INFO=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")
RELEASE_TAG=$(echo "$RELEASE_INFO" | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)

if [ -z "$RELEASE_TAG" ]; then
    echo "❌ Error: Could not fetch latest release from GitHub"
    exit 1
fi

echo "✓ Found release: $RELEASE_TAG"

# Determine which package to download (CLI on macOS 13+)
if [[ $(sw_vers -productVersion) == 1[3-9]* ]] || [[ $(sw_vers -productVersion) == [2-9][0-9]* ]]; then
    # macOS 13 or later - download CLI package
    PKG_NAME="swiftpkg-${RELEASE_TAG#v}-cli.pkg"
    DOWNLOAD_URL="https://github.com/$REPO/releases/download/$RELEASE_TAG/$PKG_NAME"
else
    echo "⚠️  Warning: swiftpkg CLI requires macOS 13 or later"
    echo "   Your macOS version: $(sw_vers -productVersion)"
    exit 1
fi

echo "Downloading: $PKG_NAME"
cd "$DOWNLOAD_DIR"

# Download the package and SHA256SUMS
curl -L -o "$PKG_NAME" "$DOWNLOAD_URL"
curl -L -o "SHA256SUMS" "https://github.com/$REPO/releases/download/$RELEASE_TAG/SHA256SUMS"

if [ ! -f "$PKG_NAME" ]; then
    echo "❌ Error: Failed to download package"
    exit 1
fi

echo "✓ Downloaded: $PKG_NAME"

# Verify SHA256 checksum
echo ""
echo "Verifying SHA256 checksum..."
if grep " $PKG_NAME$" SHA256SUMS | shasum -a 256 -c -; then
    echo "✓ SHA256 checksum verified"
else
    echo "❌ SHA256 checksum verification failed"
    rm -f "$PKG_NAME" "SHA256SUMS"
    exit 1
fi

# Verify package signature
echo ""
if ! verify_swiftpkg_package "$PKG_NAME"; then
    rm -f "$PKG_NAME" "SHA256SUMS"
    exit 1
fi

echo ""
echo "Package ready: $(pwd)/$PKG_NAME"
echo ""

if [ "$INSTALL" = true ]; then
    echo "Installing swiftpkg..."
    sudo installer -pkg "$PKG_NAME" -target /
    echo "✓ Installation complete"
    echo ""
    echo "Verify installation:"
    echo "  swiftpkg --version"
else
    echo "To install:"
    echo "  sudo installer -pkg $PKG_NAME -target /"
    echo ""
    echo "To clean up:"
    echo "  rm $PKG_NAME SHA256SUMS"
fi
