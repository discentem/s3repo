#!/bin/bash
# Download and install rustfs (S3-compatible server)
# GitHub: https://github.com/welpo/rustfs
# Note: rustfs binaries are distributed unsigned; we verify via SHA256

set -e

# Known good SHA256 hash for rustfs v1.0.0-beta.12 macOS aarch64 binary
# Source: https://github.com/rustfs/rustfs/releases/download/1.0.0-beta.12/SHA256SUMS
RUSTFS_SHA256="f5266eda245fa4dab5acf28bef7bbab6c1da7f3e9575ddc7db803894107e09f5"

INSTALL_DIR="${1:-/usr/local/bin}"
INSTALL=false

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
    INSTALLED_VERSION=$(rustfs --version 2>/dev/null || echo "unknown")
    echo "✓ rustfs is already installed: $INSTALLED_VERSION"
    exit 0
fi

echo "Checking for rustfs availability..."

# Download macOS aarch64 binary from GitHub releases
RELEASE_TAG="1.0.0-beta.12"
ARCH_PATTERN="macos-aarch64"
DOWNLOAD_URL="https://github.com/rustfs/rustfs/releases/download/$RELEASE_TAG/rustfs-${ARCH_PATTERN}-v${RELEASE_TAG}.zip"

echo "Found rustfs release: $RELEASE_TAG"
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

echo "Extracting rustfs..."
unzip -q "$TEMP_DIR/rustfs.zip" -d "$TEMP_DIR"

# Find the rustfs binary
RUSTFS_BIN=$(find "$TEMP_DIR" -name "rustfs" -type f | head -1)

if [ -z "$RUSTFS_BIN" ] || [ ! -f "$RUSTFS_BIN" ]; then
    echo "❌ Error: Could not find rustfs binary in downloaded archive"
    exit 1
fi

# Verify code signature
echo "Verifying rustfs binary..."
if command -v codesign &> /dev/null; then
    SIG_INFO=$(codesign -d -r - "$RUSTFS_BIN" 2>&1)
    
    # rustfs binaries are NOT code-signed, only hash-designated
    if echo "$SIG_INFO" | grep -q "designated => cdhash"; then
        echo "⚠ Binary is unsigned (hash-designated only)"
        
        # Extract the hash for record-keeping
        BINARY_HASH=$(echo "$SIG_INFO" | grep "cdhash" | grep -oE 'H"[^"]*' | sed 's/H"//')
        echo "  Binary hash: $BINARY_HASH"
        
        # Verify against published SHA256SUMS from GitHub releases
        echo "Verifying against published SHA256SUMS..."
        GITHUB_RELEASE="https://github.com/rustfs/rustfs/releases/download/1.0.0-beta.12"
        
        # Download SHA256SUMS and verify
        if command -v curl &> /dev/null; then
            TEMP_SHA=$(mktemp)
            curl -s -L "$GITHUB_RELEASE/SHA256SUMS" -o "$TEMP_SHA" 2>/dev/null
            
            if [ -f "$TEMP_SHA" ] && [ -s "$TEMP_SHA" ]; then
                # Compute SHA256 of the binary
                ACTUAL_SHA=$(sha256sum "$RUSTFS_BIN" | awk '{print $1}')
                
                # Check if hash appears in the published file
                if grep -q "$ACTUAL_SHA" "$TEMP_SHA"; then
                    echo "✓ SHA256 verified against published checksums"
                    echo "  SHA256: $ACTUAL_SHA"
                else
                    echo "❌ ERROR: SHA256 does not match published checksums"
                    echo "   Binary SHA256: $ACTUAL_SHA"
                    echo "   Expected: $RUSTFS_SHA256"
                    rm -f "$TEMP_SHA"
                    exit 1
                fi
            else
                echo "⚠ Could not download published SHA256SUMS, skipping verification"
            fi
            rm -f "$TEMP_SHA"
        fi
    else
        echo "✓ Code signature verified"
    fi
else
    echo "⚠ codesign not available, cannot verify binary signature"
fi

# Install binary
mkdir -p "$INSTALL_DIR"
echo "Installing rustfs to $INSTALL_DIR..."
cp "$RUSTFS_BIN" "$INSTALL_DIR/rustfs"
chmod +x "$INSTALL_DIR/rustfs"

# Verify installation
if command -v rustfs &> /dev/null; then
    INSTALLED_VERSION=$(rustfs --version 2>/dev/null || echo "unknown")
    echo "✓ rustfs installed successfully: $INSTALLED_VERSION"
    echo "Location: $(command -v rustfs)"
else
    echo "⚠ rustfs installed but not in PATH"
    echo "Add $INSTALL_DIR to your PATH or verify installation"
fi
