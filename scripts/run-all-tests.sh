#!/bin/bash
# Master test script that runs all setup and test steps in order
# This orchestrates the complete local testing workflow for S3Repo plugin

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUSTFS_BIN="/usr/local/bin/rustfs"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_section() {
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

error_exit() {
    echo -e "${RED}❌ Error: $1${NC}"
    exit 1
}

# Parse arguments
SKIP_INSTALLS=false
KEEP_SERVER_RUNNING=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-installs)
            SKIP_INSTALLS=true
            shift
            ;;
        --keep-server)
            KEEP_SERVER_RUNNING=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Runs complete local testing workflow for S3Repo plugin"
            echo ""
            echo "Options:"
            echo "  --skip-installs    Skip dependency installation steps"
            echo "  --keep-server      Keep rustfs server running after tests"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Cleanup trap to stop rustfs server if needed
RUSTFS_PID=""
cleanup() {
    if [ -n "$RUSTFS_PID" ] && ! [ "$KEEP_SERVER_RUNNING" = true ]; then
        echo ""
        echo "Stopping rustfs server (PID: $RUSTFS_PID)..."
        kill "$RUSTFS_PID" 2>/dev/null || true
        wait "$RUSTFS_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# ========== Install Dependencies ==========
if [ "$SKIP_INSTALLS" = false ]; then
    log_section "STEP 1: Installing Dependencies"
    
    echo "Installing swiftpkg..."
    "$SCRIPT_DIR/install-swiftpkg.sh" --install || error_exit "Failed to install swiftpkg"
    
    echo "Installing AWS CLI..."
    "$SCRIPT_DIR/install-awscli.sh" --install || error_exit "Failed to install AWS CLI"
    
    echo "Installing munkitools..."
    "$SCRIPT_DIR/install-munkitools.sh" --install || error_exit "Failed to install munkitools"
    
    echo "Installing rustfs..."
    "$SCRIPT_DIR/install-rustfs.sh" --install || error_exit "Failed to install rustfs"
else
    log_section "Skipping Dependency Installation (--skip-installs)"
fi

# ========== Build Plugin ==========
log_section "STEP 2: Building S3Repo Plugin"
"$SCRIPT_DIR/build-plugin-package.sh" || error_exit "Failed to build plugin"

# ========== Install Plugin ==========
log_section "STEP 3: Installing S3Repo Plugin"
"$SCRIPT_DIR/install-plugin-package.sh" || error_exit "Failed to install plugin"

# ========== Start rustfs Server ==========
log_section "STEP 4: Starting rustfs S3 Server"
# start-rustfs.sh backgrounds the actual server itself and prints its real PID
# on stdout, so it must run in the foreground here (not backgrounded with &)
# or RUSTFS_PID below would capture the wrapper script's PID instead, leaving
# the real server un-killable and leaked after this script exits.
RUSTFS_PID=$("$SCRIPT_DIR/start-rustfs.sh" --bin "$RUSTFS_BIN") || error_exit "Failed to start rustfs server"
echo "rustfs started with PID: $RUSTFS_PID"

# Wait for server to be ready
echo "Waiting for rustfs to be ready..."
for i in {1..30}; do
    if nc -z localhost 9000 2>/dev/null; then
        echo "✓ rustfs is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        error_exit "rustfs server did not start"
    fi
    sleep 1
done

# ========== Setup S3 Repository ==========
log_section "STEP 5: Setting up S3 Repository"
"$SCRIPT_DIR/setup-s3-repo.sh" || error_exit "Failed to setup S3 repo"

# ========== Run Tests ==========
log_section "STEP 6: Running munkiimport Test"
"$SCRIPT_DIR/test_munkiimport.sh" || error_exit "munkiimport test failed"

log_section "STEP 7: Running makecatalogs Test"
"$SCRIPT_DIR/test-makecatalogs.sh" || error_exit "makecatalogs test failed"

log_section "STEP 8: Running repoclean Test"
"$SCRIPT_DIR/test-repoclean.sh" || error_exit "repoclean test failed"

# ========== Complete ==========
log_section "✓ All Tests Completed Successfully!"

if [ "$KEEP_SERVER_RUNNING" = true ]; then
    echo "rustfs server is still running with PID: $RUSTFS_PID"
    echo "S3 repo available at: http://localhost:9000/munki-repo"
    echo ""
    echo "To stop the server later, run:"
    echo "  kill $RUSTFS_PID"
else
    echo "rustfs server will be stopped on exit"
fi
