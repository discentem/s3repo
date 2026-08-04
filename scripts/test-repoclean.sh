#!/bin/bash
# Test script for repoclean with the S3Repo plugin
# Assumes rustfs server and S3 bucket are already setup
# Tests repository cleanup functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# /usr/local/munki isn't on PATH by default (e.g. on GitHub Actions runners)
REPOCLEAN_BIN="/usr/local/munki/repoclean"
MUNKIIMPORT_BIN="/usr/local/munki/munkiimport"

SWIFTPKG_BIN="/usr/local/bin/swiftpkg"
if [ ! -x "$SWIFTPKG_BIN" ]; then
    if command -v swiftpkg &> /dev/null; then
        SWIFTPKG_BIN="$(command -v swiftpkg)"
    fi
fi

# Parse arguments
REPO_URL="http://localhost:9000/munki-repo"

while [[ $# -gt 0 ]]; do
    case $1 in
        --repo-url)
            REPO_URL="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Test repoclean with S3Repo plugin"
            echo ""
            echo "Options:"
            echo "  --repo-url URL    S3 repository URL (default: http://localhost:9000/munki-repo)"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ ! -x "$REPOCLEAN_BIN" ]; then
    echo "❌ Error: $REPOCLEAN_BIN not found or not executable"
    exit 1
fi

if [ ! -x "$MUNKIIMPORT_BIN" ]; then
    echo "❌ Error: $MUNKIIMPORT_BIN not found or not executable"
    exit 1
fi

if [ ! -x "$SWIFTPKG_BIN" ]; then
    echo "❌ Error: swiftpkg not found or not executable"
    exit 1
fi

echo "Running repoclean test with:"
echo "  Repo URL: $REPO_URL"
echo ""

# Show initial repo state
echo "=== Repository State Before repoclean ==="
echo ""
echo "Manifests:"
AWS_ACCESS_KEY_ID="blah" \
AWS_SECRET_ACCESS_KEY="blah" \
aws s3 ls "s3://munki-repo/manifests/" \
    --endpoint-url "http://localhost:9000" \
    --region "us-east-1" || {
    echo "No manifests found"
}

echo ""
echo "Packages:"
AWS_ACCESS_KEY_ID="blah" \
AWS_SECRET_ACCESS_KEY="blah" \
aws s3 ls "s3://munki-repo/pkgs/" \
    --endpoint-url "http://localhost:9000" \
    --region "us-east-1" --recursive || {
    echo "No packages found"
}

echo ""
echo "=== Building & Importing Ephemeral Extra Package Versions ==="
# repoclean's default --keep is 2 (keep newest 2 versions of an item), so with
# only one real version present nothing would ever be flagged for cleanup.
# Build two more real packages with bumped versions (repackaging the already-
# built payload via swiftpkg against a copy of build-info.yaml with the version
# field changed) and import them normally, so there are 3 real versions and the
# oldest is the one repoclean should report cleaning up.
S3REPO_PACKAGE_DIR="$PROJECT_ROOT/S3RepoPackage"
EPHEMERAL_TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$EPHEMERAL_TEMP_DIR"' EXIT

for FAKE_VERSION in 1.1.0 1.2.0; do
    VERSION_PROJECT_DIR="$EPHEMERAL_TEMP_DIR/S3RepoPackage-$FAKE_VERSION"
    cp -R "$S3REPO_PACKAGE_DIR" "$VERSION_PROJECT_DIR"
    rm -rf "$VERSION_PROJECT_DIR/build"
    sed -i '' "s/^version: .*/version: $FAKE_VERSION/" "$VERSION_PROJECT_DIR/build-info.yaml"

    echo "Building ephemeral package version $FAKE_VERSION..."
    "$SWIFTPKG_BIN" "$VERSION_PROJECT_DIR" || {
        echo "❌ Failed to build ephemeral package version $FAKE_VERSION"
        exit 1
    }

    FAKE_PKG_PATH="$VERSION_PROJECT_DIR/build/S3RepoPlugin.pkg"
    if [ ! -f "$FAKE_PKG_PATH" ]; then
        echo "❌ Ephemeral package not found at $FAKE_PKG_PATH"
        exit 1
    fi

    echo "Importing ephemeral package version $FAKE_VERSION..."
    # --extract-icon avoids the "Attempt to create a product icon? [y/N]"
    # interactive prompt that -n alone doesn't suppress
    AWS_ACCESS_KEY_ID="blah" \
    AWS_SECRET_ACCESS_KEY="blah" \
    "$MUNKIIMPORT_BIN" "$FAKE_PKG_PATH" \
        -n \
        --subdirectory "S3RepoPlugin" \
        --plugin "S3Repo" \
        --repo-url "$REPO_URL" \
        --extract-icon || {
        echo "❌ Failed to import ephemeral package version $FAKE_VERSION"
        exit 1
    }
    echo "✓ Imported ephemeral version $FAKE_VERSION"
done

echo ""
echo "=== Running repoclean Test ==="

# Run repoclean with AWS credentials for S3 backend
# repoclean cleans up orphaned packages and unused pkginfo entries
# repoclean has no --dry-run or -v/-vvv flags; --show-all without --auto
# reports what would be deleted without prompting or deleting anything
AWS_ACCESS_KEY_ID="blah" \
AWS_SECRET_ACCESS_KEY="blah" \
"$REPOCLEAN_BIN" \
    --plugin S3Repo \
    --repo-url "$REPO_URL" \
    --show-all 2>&1 &

REPOCLEAN_PID=$!

# Implement timeout manually (macOS has no GNU `timeout`)
(
    sleep 30
    if kill -0 "$REPOCLEAN_PID" 2>/dev/null; then
        echo "ERROR: repoclean timed out after 30 seconds"
        kill -TERM "$REPOCLEAN_PID" 2>/dev/null
    fi
) &
WATCHER_PID=$!

if wait "$REPOCLEAN_PID"; then
    EXIT_CODE=0
else
    EXIT_CODE=$?
fi

kill "$WATCHER_PID" 2>/dev/null || true
wait "$WATCHER_PID" 2>/dev/null || true

echo ""
echo "repoclean exited with code: $EXIT_CODE"

# Show final repo state
echo ""
echo "=== Repository State After repoclean (dry-run) ==="
echo ""
echo "Manifests:"
AWS_ACCESS_KEY_ID="blah" \
AWS_SECRET_ACCESS_KEY="blah" \
aws s3 ls "s3://munki-repo/manifests/" \
    --endpoint-url "http://localhost:9000" \
    --region "us-east-1" || {
    echo "No manifests found"
}

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ repoclean test passed (dry-run completed successfully)"
    echo "Note: This was a dry-run. No actual cleanup was performed."
else
    echo "❌ repoclean test failed"
fi

exit $EXIT_CODE
