#!/bin/bash
# Test script for makecatalogs with the S3Repo plugin
# Assumes rustfs server and S3 bucket are already setup
# Creates test pkginfo entries and builds catalogs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# /usr/local/munki isn't on PATH by default (e.g. on GitHub Actions runners)
MAKECATALOGS_BIN="/usr/local/munki/makecatalogs"

# Parse arguments
REPO_URL="http://localhost:9000/munki-repo"
CATALOG_NAME="testing"

while [[ $# -gt 0 ]]; do
    case $1 in
        --repo-url)
            REPO_URL="$2"
            shift 2
            ;;
        --catalog)
            CATALOG_NAME="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Test makecatalogs with S3Repo plugin"
            echo ""
            echo "Options:"
            echo "  --repo-url URL    S3 repository URL (default: http://localhost:9000/munki-repo)"
            echo "  --catalog NAME    Catalog name to use (default: testing)"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ ! -x "$MAKECATALOGS_BIN" ]; then
    echo "❌ Error: $MAKECATALOGS_BIN not found or not executable"
    exit 1
fi

echo "Running makecatalogs test with:"
echo "  Repo URL: $REPO_URL"
echo "  Catalog: $CATALOG_NAME"
echo ""

echo "=== Running makecatalogs Test (reading from S3 backend) ==="

# Run makecatalogs with AWS credentials for S3 backend
# The repo will read pkginfo directly from the S3 backend
# makecatalogs has no -n or -v/-vvv flags; --repo-url must be passed as a flag.
# -s/--skip-pkg-check is required: pathFor() returns an s3:// URI, which isn't
# a local filesystem path, so the default pkg-existence sanity check always fails.
AWS_ACCESS_KEY_ID="blah" \
AWS_SECRET_ACCESS_KEY="blah" \
"$MAKECATALOGS_BIN" \
    --plugin S3Repo \
    --repo-url "$REPO_URL" \
    --skip-pkg-check 2>&1 &

MAKECATALOGS_PID=$!

# Implement timeout manually (macOS has no GNU `timeout`)
(
    sleep 30
    if kill -0 "$MAKECATALOGS_PID" 2>/dev/null; then
        echo "ERROR: makecatalogs timed out after 30 seconds"
        kill -TERM "$MAKECATALOGS_PID" 2>/dev/null
    fi
) &
WATCHER_PID=$!

if wait "$MAKECATALOGS_PID"; then
    EXIT_CODE=0
else
    EXIT_CODE=$?
fi

kill "$WATCHER_PID" 2>/dev/null || true
wait "$WATCHER_PID" 2>/dev/null || true

echo ""
echo "makecatalogs exited with code: $EXIT_CODE"

if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ makecatalogs test passed"
    
    # Verify catalog was created
    echo ""
    echo "Checking if catalog was created in S3 bucket..."
    AWS_ACCESS_KEY_ID="blah" \
    AWS_SECRET_ACCESS_KEY="blah" \
    aws s3 ls "s3://munki-repo/catalogs/" \
        --endpoint-url "http://localhost:9000" \
        --region "us-east-1" || {
        echo "⚠ Warning: Could not verify catalog creation"
    }
fi

exit $EXIT_CODE
