#!/bin/sh
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

check_exit_code() {
    if [ "$1" != "0" ]; then
        echo "$2: $1" 1>&2
        exit 1
    fi
}

TOOL="S3Repo"
VERSION="1.0.0"

# Check if swiftpkg is installed
SWIFTPKG_PATH="/usr/local/bin/swiftpkg"
if [ ! -f "$SWIFTPKG_PATH" ]; then
    if ! command -v swiftpkg &> /dev/null; then
        echo "Error: swiftpkg is not installed"
        echo ""
        echo "Install swiftpkg via Homebrew:"
        echo "  brew install codecarton/tap/swiftpkg"
        echo ""
        echo "Or use the install script:"
        echo "  ./scripts/install-swiftpkg.sh --install"
        exit 1
    fi
    SWIFTPKG="swiftpkg"
else
    SWIFTPKG="$SWIFTPKG_PATH"
fi

# Get script directory
THISDIR=$(dirname "$0")
cd "$THISDIR"
THISDIR=$(pwd)
PROJECT_ROOT=$(dirname "$THISDIR")

echo "Building ${TOOL} plugin..."

# Build only the S3Repo product (not MunkiRepoInit)
cd "$PROJECT_ROOT"
swift build -c release --product S3Repo
check_exit_code "$?" "Error building ${TOOL}"

# Find the built product and copy to payload
PAYLOAD_DIR="S3RepoPackage/payload/usr/local/munki/repoplugins"
rm -rf "$PAYLOAD_DIR"
mkdir -p "$PAYLOAD_DIR"
chmod -R 755 "S3RepoPackage/payload"

# Build creates the dylib automatically with type: .dynamic in Package.swift
echo "Staging S3Repo library..."

# Find the architecture
ARCH=$(arch)
if [ "$ARCH" = "arm64" ]; then
    BUILD_ARCH="arm64-apple-macosx"
else
    BUILD_ARCH="x86_64-apple-macosx"
fi

DYLIB_PATH=".build/${BUILD_ARCH}/release/libS3Repo.dylib"

# Copy the dylib to the payload directory
if [ -f "$DYLIB_PATH" ]; then
    cp "$DYLIB_PATH" "$PAYLOAD_DIR/S3Repo.plugin"
    chmod 755 "$PAYLOAD_DIR/S3Repo.plugin"
else
    check_exit_code 1 "Failed to find S3Repo dylib at $DYLIB_PATH"
fi

if [ ! -f "$PAYLOAD_DIR/S3Repo.plugin" ]; then
    check_exit_code 1 "Failed to stage S3Repo library"
fi

# Use swiftpkg to build the installer package
echo "Building pkg with swiftpkg..."
"$SWIFTPKG" S3RepoPackage
check_exit_code "$?" "Error building package with swiftpkg"

echo ""
echo "✓ Package created: S3RepoPackage/build/S3RepoPlugin.pkg"
echo ""
echo "To install:"
echo "  sudo installer -pkg S3RepoPackage/build/S3RepoPlugin.pkg -target /"
