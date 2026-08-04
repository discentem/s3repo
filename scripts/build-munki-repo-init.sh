#!/bin/bash
# Build the MunkiRepoInit tool for creating S3 buckets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Building MunkiRepoInit tool..."

cd "$PROJECT_ROOT"
swift build -c release --product MunkiRepoInit

ARCH=$(arch)
if [ "$ARCH" = "arm64" ]; then
    BUILD_ARCH="arm64-apple-macosx"
else
    BUILD_ARCH="x86_64-apple-macosx"
fi

TOOL_PATH=".build/${BUILD_ARCH}/release/MunkiRepoInit"

if [ ! -f "$TOOL_PATH" ]; then
    echo "❌ Error: MunkiRepoInit tool not found at $TOOL_PATH"
    exit 1
fi

echo "✓ MunkiRepoInit tool built successfully"
echo "  Location: $TOOL_PATH"
