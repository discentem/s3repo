#!/bin/bash
# Non-interactive test script for munkiimport with end-to-end server setup
set -e

APP_PATH="${1:-/Applications/Ghostty.app}"
REPO_URL="${2:-http://localhost:9000/munki-repo}"
PLUGIN="${3:-S3Repo}"
SETUP_SERVER="${4:-true}"  # Set to false to skip server/bucket setup
KEEP_RUSTFS_ALIVE="${5:-true}"  # Set to true to keep rustfs server running after test

# Cleanup function for trap
cleanup() {
    echo ""
    if [ "$KEEP_RUSTFS_ALIVE" = "true" ]; then
        echo "Test complete. rustfs server is still running (PID: $RUSTFS_PID)"
        echo "To stop it: kill $RUSTFS_PID"
        # Don't trap EXIT since server should stay alive
        trap - EXIT
    else
        echo "Cleaning up..."
        # Kill rustfs server if it's running
        if [ -n "$RUSTFS_PID" ] && kill -0 "$RUSTFS_PID" 2>/dev/null; then
            echo "Stopping rustfs server (PID: $RUSTFS_PID)..."
            kill "$RUSTFS_PID" 2>/dev/null || true
            wait "$RUSTFS_PID" 2>/dev/null || true
        fi
    fi
}

trap cleanup EXIT

if [ ! -e "$APP_PATH" ]; then
    echo "Error: $APP_PATH not found"
    exit 1
fi

echo "Testing munkiimport with:"
echo "  App: $APP_PATH"
echo "  Repo URL: $REPO_URL"
echo "  Plugin: $PLUGIN"
echo "  Setup Server: $SETUP_SERVER"
echo ""

# Setup server and bucket if requested
if [ "$SETUP_SERVER" = "true" ]; then
    echo "=== Starting S3 Server Setup ==="
    
    # Check if rustfs is available
    if ! command -v rustfs &> /dev/null; then
        echo "Error: rustfs not found in PATH"
        exit 1
    fi
    
    # Create rustfs storage directory
    RUSTFS_DIR="${HOME}/.s3repo-test-buckets"
    mkdir -p "$RUSTFS_DIR"
    
    # Start rustfs server in background
    echo "Starting rustfs server at $RUSTFS_DIR..."
    rustfs server "$RUSTFS_DIR" \
        --console-enable \
        --access-key="blah" \
        --secret-key="blah" &
    RUSTFS_PID=$!
    
    # Wait for server to start
    echo "Waiting for rustfs server to be ready..."
    sleep 2
    
    # Check if server is running
    if ! kill -0 "$RUSTFS_PID" 2>/dev/null; then
        echo "Error: rustfs server failed to start"
        exit 1
    fi
    
    echo "✓ rustfs server started (PID: $RUSTFS_PID)"
    
    # Find and run the bucket setup tool (should exist from build-plugin-package.sh)
    echo "Setting up S3 bucket..."
    
    BUCKET_TOOL=".build/arm64-apple-macosx/release/MunkiRepoInit"
    if [ ! -f "$BUCKET_TOOL" ]; then
        BUCKET_TOOL=".build/x86_64-apple-macosx/release/MunkiRepoInit"
    fi
    
    if [ ! -f "$BUCKET_TOOL" ]; then
        echo "Error: MunkiRepoInit tool not found. Make sure to run build-plugin-package.sh first."
        exit 1
    fi
    
    # Extract bucket name from repo URL
    # From http://localhost:9000/munki-repo, extract "munki-repo"
    BUCKET_NAME=$(echo "$REPO_URL" | sed -n 's|^https*://[^/]*/\([^/]*\).*|\1|p')
    if [ -z "$BUCKET_NAME" ]; then
        BUCKET_NAME="munki-repo"
    fi
    
    echo "Setting up S3 bucket: $BUCKET_NAME"
    AWS_ACCESS_KEY_ID="blah" \
    AWS_SECRET_ACCESS_KEY="blah" \
    "$BUCKET_TOOL" "$BUCKET_NAME" --endpoint "http://localhost:9000" --region "us-east-1" 2>&1 | head -20 || true
    
    echo "✓ S3 bucket initialized"
    echo ""
fi

echo "=== Running munkiimport Test ==="
# Run munkiimport non-interactively with AWS credentials
# -n: no interactive prompts
# --subdirectory: where to upload in repo
# --plugin: which plugin to use
# -vvv: very verbose output
# timeout after 30 seconds if command is available

# Determine timeout command to use
TIMEOUT_CMD=""
if command -v gtimeout &> /dev/null; then
    TIMEOUT_CMD="gtimeout 30"
elif command -v timeout &> /dev/null; then
    TIMEOUT_CMD="timeout 30"
fi

if [ -n "$TIMEOUT_CMD" ]; then
    $TIMEOUT_CMD bash -c 'AWS_ACCESS_KEY_ID="blah" \
AWS_SECRET_ACCESS_KEY="blah" \
munkiimport "$APP_PATH" \
    -n \
    --subdirectory "Test" \
    --plugin "$PLUGIN" \
    --repo-url "$REPO_URL" \
    --extract-icon \
    -vvv 2>&1' || {
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 124 ]; then
            echo "ERROR: munkiimport timed out after 30 seconds"
        fi
        exit $EXIT_CODE
    }
else
    # No timeout available, run without it
    AWS_ACCESS_KEY_ID="blah" \
    AWS_SECRET_ACCESS_KEY="blah" \
    munkiimport "$APP_PATH" \
        -n \
        --subdirectory "Test" \
        --plugin "$PLUGIN" \
        --repo-url "$REPO_URL" \
        --extract-icon \
        -vvv 2>&1 || {
        EXIT_CODE=$?
        exit $EXIT_CODE
    }
fi

EXIT_CODE=$?
echo ""
echo "munkiimport exited with code: $EXIT_CODE"
exit $EXIT_CODE
