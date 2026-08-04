#!/bin/bash
# Install the S3Repo plugin package created by build-plugin-package.sh

set -e

PACKAGE_PATH=""
BUILD_FIRST=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --pkg)
            PACKAGE_PATH="$2"
            shift 2
            ;;
        --build)
            BUILD_FIRST=false
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --pkg PATH        Path to the .pkg file to install"
            echo "  --build           Build the package first using build-plugin-package.sh"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Build package if requested
if [ "$BUILD_FIRST" = true ]; then
    echo "Building plugin package..."
    "$SCRIPT_DIR/build-plugin-package.sh"
fi

# Determine package path
if [ -z "$PACKAGE_PATH" ]; then
    # Look for the default package location
    PACKAGE_PATH="$PROJECT_ROOT/S3RepoPackage/build/S3RepoPlugin.pkg"
    
    if [ ! -f "$PACKAGE_PATH" ]; then
        echo "❌ Error: Package not found at $PACKAGE_PATH"
        echo ""
        echo "Build the package first:"
        echo "  $SCRIPT_DIR/build-plugin-package.sh"
        echo ""
        echo "Or specify a custom package path:"
        echo "  $0 --pkg /path/to/S3RepoPlugin.pkg"
        exit 1
    fi
fi

# Verify the package exists
if [ ! -f "$PACKAGE_PATH" ]; then
    echo "❌ Error: Package not found at $PACKAGE_PATH"
    exit 1
fi

echo "Installing S3Repo plugin from: $PACKAGE_PATH"
echo ""

# Install the package with admin privileges
sudo installer -pkg "$PACKAGE_PATH" -target /

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ S3Repo plugin installed successfully"
else
    echo ""
    echo "❌ Failed to install S3Repo plugin"
    exit 1
fi
