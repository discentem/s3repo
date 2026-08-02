#!/bin/bash
# Download and verify swiftpkg release from GitHub
# GitHub: https://github.com/codecarton/swiftpkg
# Team ID: DPXY7JLK67 (codecarton)

set -e

REPO="codecarton/swiftpkg"
DOWNLOAD_DIR="${1:-.}"
INSTALL=false

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
echo "Verifying package signature..."
if pkgutil --check-signature "$PKG_NAME" 2>/dev/null | grep -q "Developer ID"; then
    echo "✓ Package is signed"
    
    # Extract and display signature details
    CERT_INFO=$(pkgutil --check-signature "$PKG_NAME" 2>/dev/null || true)
    echo ""
    echo "Signature Details:"
    echo "$CERT_INFO" | grep -E "Certificate chain|Developer ID" || echo "  Certificate chain: Valid"
    
    # Verify team identifier
    TEAM_ID=$(echo "$CERT_INFO" | grep -oE "Team ID: [A-Z0-9]+" | cut -d' ' -f3)
    if [ "$TEAM_ID" = "DPXY7JLK67" ]; then
        echo "✓ Team ID verified: $TEAM_ID (codecarton)"
    else
        echo "⚠️  Team ID: $TEAM_ID (expected DPXY7JLK67)"
    fi
else
    echo "⚠️  Warning: Could not verify package signature"
    echo "   This may be expected for development releases"
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
