#!/bin/bash
# Download and install rustfs (S3-compatible server)
# GitHub: https://github.com/welpo/rustfs
# Pinned to: v1.0.0-beta.12 macOS aarch64 binary

set -e

# Pinned release with SHA256 hash for verification
RUSTFS_VERSION="1.0.0-beta.12"
RUSTFS_BINARY_SHA256="0f9dedc7c606fe133ed33cc27464cc64705544e4e1360673f4c5e8a78e931bce"

INSTALL_DIR="${1:-/usr/local/bin}"
INSTALL=false

# Verify rustfs binary hash
verify_rustfs_binary() {
    local binary_path="$1"
    if [ ! -f "$binary_path" ]; then
        echo "❌ Error: rustfs binary not found at $binary_path"
        return 1
    fi
    
    local binary_sha=$(sha256sum "$binary_path" | awk '{print $1}')
    if [ "$binary_sha" != "$RUSTFS_BINARY_SHA256" ]; then
        echo "❌ ERROR: Binary SHA256 does not match pinned hash"
        echo "   Got:      $binary_sha"
        echo "   Expected: $RUSTFS_BINARY_SHA256"
        return 1
    fi
    return 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --install)
            INSTALL=true
            shift
            ;;
        --dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dir DIR         Installation directory (default: /usr/local/bin)"
            echo "  --install         Install after download"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if rustfs is already installed
if command -v rustfs &> /dev/null; then
    RUSTFS_BIN=$(command -v rustfs)
    echo "Found rustfs at: $RUSTFS_BIN"
    
    echo "Verifying rustfs binary hash..."
    if verify_rustfs_binary "$RUSTFS_BIN"; then
        INSTALLED_VERSION=$(rustfs --version 2>/dev/null || echo "unknown")
        echo "✓ rustfs is already installed and verified: $INSTALLED_VERSION"
        exit 0
    else
        echo "❌ ERROR: Installed rustfs binary failed verification"
        exit 1
    fi
fi

echo "Checking for rustfs availability..."

# Download macOS aarch64 binary from GitHub releases (pinned version)
ARCH_PATTERN="macos-aarch64"
DOWNLOAD_URL="https://github.com/rustfs/rustfs/releases/download/${RUSTFS_VERSION}/rustfs-${ARCH_PATTERN}-v${RUSTFS_VERSION}.zip"

echo "Found rustfs release: $RUSTFS_VERSION"
echo "Download URL: $DOWNLOAD_URL"

if [ "$INSTALL" = false ]; then
    echo ""
    echo "To install rustfs, run:"
    echo "  $0 --install"
    exit 0
fi

# Check for required tools
if ! command -v unzip &> /dev/null; then
    echo "❌ Error: unzip is required but not found"
    exit 1
fi

# Create temporary directory for download
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Downloading rustfs..."
if ! curl -L -o "$TEMP_DIR/rustfs.zip" "$DOWNLOAD_URL"; then
    echo "❌ Error: Failed to download rustfs"
    exit 1
fi

echo "Verifying download integrity..."
DOWNLOADED_SHA=$(sha256sum "$TEMP_DIR/rustfs.zip" | awk '{print $1}')
if [ "$DOWNLOADED_SHA" != "$RUSTFS_BINARY_SHA256" ]; then
    echo "❌ ERROR: Downloaded file SHA256 does not match pinned hash"
    echo "   Downloaded: $DOWNLOADED_SHA"
    echo "   Expected:   $RUSTFS_BINARY_SHA256"
    exit 1
fi
echo "✓ Download integrity verified"

echo "Extracting rustfs..."
unzip -q "$TEMP_DIR/rustfs.zip" -d "$TEMP_DIR"

# Find the rustfs binary
RUSTFS_BIN=$(find "$TEMP_DIR" -name "rustfs" -type f | head -1)

if [ -z "$RUSTFS_BIN" ] || [ ! -f "$RUSTFS_BIN" ]; then
    echo "❌ Error: Could not find rustfs binary in downloaded archive"
    exit 1
fi

# Verify binary hash (rustfs is distributed unsigned)
echo "Verifying rustfs binary hash..."
if ! verify_rustfs_binary "$RUSTFS_BIN"; then
    exit 1
fi
echo "✓ Binary hash verified"

# Install binary
mkdir -p "$INSTALL_DIR"
echo "Installing rustfs to $INSTALL_DIR..."
cp "$RUSTFS_BIN" "$INSTALL_DIR/rustfs"
chmod +x "$INSTALL_DIR/rustfs"

# Verify installation
if command -v rustfs &> /dev/null; then
    INSTALLED_RUSTFS_BIN=$(command -v rustfs)
    echo "Verifying installed rustfs binary hash..."
    if verify_rustfs_binary "$INSTALLED_RUSTFS_BIN"; then
        INSTALLED_VERSION=$(rustfs --version 2>/dev/null || echo "unknown")
        echo "✓ rustfs installed successfully and verified: $INSTALLED_VERSION"
        echo "Location: $INSTALLED_RUSTFS_BIN"
    else
        echo "❌ Error: Installed rustfs binary failed verification"
        exit 1
    fi
else
    echo "⚠ rustfs installed but not in PATH"
    echo "Add $INSTALL_DIR to your PATH or verify installation"
fi
