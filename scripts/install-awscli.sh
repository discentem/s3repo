#!/bin/bash
# Download and install AWS CLI with strict cryptographic verification

set -e

# AWS CLI installation configuration
EXPECTED_ISSUER="AMZN Mobile LLC"
EXPECTED_TEAM_ID="94KV3E626L"
INSTALLED_BIN_PATH="/usr/local/aws-cli/aws"

# Download URL from official AWS CDN
DOWNLOAD_URL="https://awscli.amazonaws.com/AWSCLIV2.pkg"
DOWNLOAD_DIR="/tmp"
PKG_PATH="$DOWNLOAD_DIR/AWSCLIV2.pkg"

# Verify the installed binary after installation
verify_awscli_binary() {
    local bin_path="$1"

    if [ ! -f "$bin_path" ]; then
        echo "❌ Error: AWS CLI binary not found at $bin_path"
        return 1
    fi

    if ! codesign --verify --strict "$bin_path" &>/dev/null; then
        echo "❌ Error: AWS CLI binary signature verification failed"
        return 1
    fi

    # --verify only proves the binary matches its signature (even an ad-hoc
    # one); it does NOT prove who signed it. Also check the Team ID.
    local team_id
    team_id=$(codesign -dvv "$bin_path" 2>&1 | grep "^TeamIdentifier=" | cut -d= -f2)
    if [ "$team_id" != "$EXPECTED_TEAM_ID" ]; then
        echo "❌ Error: Installed binary Team ID mismatch!"
        echo "   Expected: $EXPECTED_TEAM_ID"
        echo "   Got: ${team_id:-not set}"
        return 1
    fi

    echo "✓ AWS CLI binary signature verified (Team ID: $team_id)"
    return 0
}

echo "Installing AWS CLI from official AWS CDN..."

# Check if AWS CLI is already installed at the known location
if [ -f "$INSTALLED_BIN_PATH" ]; then
    echo "Found existing AWS CLI at: $INSTALLED_BIN_PATH"
    if verify_awscli_binary "$INSTALLED_BIN_PATH"; then
        INSTALLED_VERSION=$("$INSTALLED_BIN_PATH" --version)
        echo "✓ AWS CLI already installed and verified: $INSTALLED_VERSION"
        exit 0
    else
        echo "⚠ Existing AWS CLI binary failed verification, reinstalling..."
    fi
fi

# Download the package
echo "Downloading AWS CLI..."
if ! curl -L -o "$PKG_PATH" "$DOWNLOAD_URL" 2>/dev/null; then
    echo "❌ Error: Failed to download AWS CLI"
    exit 1
fi

echo "Downloaded: $(ls -lh $PKG_PATH | awk '{print $5}')"

# Verify package signature and Team ID
verify_awscli_package() {
    local pkg_path="$1"
    
    if [ ! -f "$pkg_path" ]; then
        echo "❌ Error: AWS CLI package not found at $pkg_path"
        return 1
    fi
    
    echo "Verifying AWS CLI package signature..."
    if command -v pkgutil &> /dev/null; then
        if pkgutil --check-signature "$pkg_path" &>/dev/null; then
            echo "✓ Package signature verified"
            
            # Extract and verify issuer and Team ID
            CERT_INFO=$(pkgutil --check-signature "$pkg_path" 2>&1)
            
            # Extract issuer name and Team ID from "Developer ID Installer: Name (TEAMID)" format
            ACTUAL_ISSUER=$(echo "$CERT_INFO" | grep "Developer ID Installer:" | head -1 | sed 's/.*Developer ID Installer: //' | sed 's/ (.*//')
            ACTUAL_TEAM_ID=$(echo "$CERT_INFO" | grep "Developer ID Installer:" | head -1 | grep -oE '\([A-Z0-9]+\)' | tr -d '()')
            
            if [ "$ACTUAL_ISSUER" != "$EXPECTED_ISSUER" ]; then
                echo "❌ ERROR: Issuer mismatch!"
                echo "   Expected: $EXPECTED_ISSUER"
                echo "   Got: $ACTUAL_ISSUER"
                return 1
            fi
            
            if [ "$ACTUAL_TEAM_ID" != "$EXPECTED_TEAM_ID" ]; then
                echo "❌ ERROR: Team ID mismatch!"
                echo "   Expected: $EXPECTED_TEAM_ID"
                echo "   Got: $ACTUAL_TEAM_ID"
                return 1
            fi
            
            echo "✓ Issuer verified: $ACTUAL_ISSUER ($ACTUAL_TEAM_ID)"
            return 0
        else
            echo "❌ ERROR: Package signature verification failed"
            return 1
        fi
    else
        echo "❌ ERROR: pkgutil is not available. Cannot verify package signature."
        return 1
    fi
}

# Verify the package
if ! verify_awscli_package "$PKG_PATH"; then
    rm -f "$PKG_PATH"
    exit 1
fi

# Install the package
echo "Installing AWS CLI package..."
if ! sudo installer -pkg "$PKG_PATH" -target / &>/dev/null; then
    echo "❌ Error: Failed to install AWS CLI"
    rm -f "$PKG_PATH"
    exit 1
fi

# Verify the installed binary
if ! verify_awscli_binary "$INSTALLED_BIN_PATH"; then
    rm -f "$PKG_PATH"
    exit 1
fi

# Clean up
rm -f "$PKG_PATH"

# Verify the installation
if ! command -v aws &> /dev/null; then
    echo "❌ Error: AWS CLI not found after installation"
    exit 1
fi

AWS_VERSION=$(aws --version)
echo "✓ AWS CLI installed successfully: $AWS_VERSION"

