#!/bin/bash
# Non-interactive test script for munkiimport
# Assumes rustfs server and S3 bucket are already setup
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# /usr/local/munki isn't on PATH by default (e.g. on GitHub Actions runners)
MUNKIIMPORT_BIN="/usr/local/munki/munkiimport"

# Parse arguments
APP_PATH="${PROJECT_ROOT}/S3RepoPackage/build/S3RepoPlugin.pkg"
REPO_URL="http://localhost:9000/munki-repo"
PLUGIN="S3Repo"

while [[ $# -gt 0 ]]; do
    case $1 in
        --app)
            APP_PATH="$2"
            shift 2
            ;;
        --repo-url)
            REPO_URL="$2"
            shift 2
            ;;
        --plugin)
            PLUGIN="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --app PATH             Path to application/package to import (default: S3RepoPlugin.pkg)"
            echo "  --repo-url URL         S3 repository URL (default: http://localhost:9000/munki-repo)"
            echo "  --plugin NAME          Plugin name to use (default: S3Repo)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ ! -e "$APP_PATH" ]; then
    echo "❌ Error: $APP_PATH not found"
    exit 1
fi

if [ ! -x "$MUNKIIMPORT_BIN" ]; then
    echo "❌ Error: $MUNKIIMPORT_BIN not found or not executable"
    exit 1
fi

echo "Running munkiimport test with:"
echo "  App: $APP_PATH"
echo "  Repo URL: $REPO_URL"
echo "  Plugin: $PLUGIN"
echo ""

echo "=== Running munkiimport Test ==="
# Run munkiimport non-interactively with AWS credentials
# -n: no interactive prompts
# --subdirectory: where to upload in repo
# --plugin: which plugin to use
# -vvv: very verbose output
# timeout after 30 seconds (macOS has no GNU `timeout`, so implement it manually)

AWS_ACCESS_KEY_ID="blah" \
AWS_SECRET_ACCESS_KEY="blah" \
"$MUNKIIMPORT_BIN" "$APP_PATH" \
    -n \
    --subdirectory "S3RepoPlugin" \
    --plugin "$PLUGIN" \
    --repo-url "$REPO_URL" \
    --extract-icon \
    -vvv 2>&1 &
MUNKIIMPORT_PID=$!

(
    sleep 30
    if kill -0 "$MUNKIIMPORT_PID" 2>/dev/null; then
        echo "ERROR: munkiimport timed out after 30 seconds"
        kill -TERM "$MUNKIIMPORT_PID" 2>/dev/null
    fi
) &
WATCHER_PID=$!

if wait "$MUNKIIMPORT_PID"; then
    EXIT_CODE=0
else
    EXIT_CODE=$?
fi

kill "$WATCHER_PID" 2>/dev/null || true
wait "$WATCHER_PID" 2>/dev/null || true

echo ""
echo "munkiimport exited with code: $EXIT_CODE"
exit $EXIT_CODE
