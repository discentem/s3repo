#!/bin/bash
# Full end-to-end test script: build → package → install → start server → create bucket → test
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Cleanup function to kill rustfs if it's running
cleanup() {
    if [ -n "$RUSTFS_PID" ] && kill -0 "$RUSTFS_PID" 2>/dev/null; then
        echo ""
        echo "Cleaning up rustfs server (PID: $RUSTFS_PID)..."
        kill "$RUSTFS_PID" 2>/dev/null || true
        wait "$RUSTFS_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT

echo -e "${BLUE}=== S3Repo Full End-to-End Test ===${NC}"
echo ""

# Step 1: Build plugin package (includes Swift build)
echo -e "${BLUE}[1/7] Building plugin package...${NC}"
cd "$PROJECT_ROOT"
sh "$SCRIPT_DIR/build-plugin-package.sh" 2>&1 | tail -10
echo -e "${GREEN}✓ Plugin package built${NC}"
echo ""

# Step 2: Build MunkiRepoInit tool
echo -e "${BLUE}[2/7] Building MunkiRepoInit tool...${NC}"
sh "$SCRIPT_DIR/build-munki-repo-init.sh" 2>&1 | tail -5
echo -e "${GREEN}✓ MunkiRepoInit tool built${NC}"
echo ""

# Step 3: Install plugin package
echo -e "${BLUE}[3/7] Installing plugin package...${NC}"
sudo sh "$SCRIPT_DIR/install-plugin-package.sh" 2>&1 | tail -5
echo -e "${GREEN}✓ Plugin installed${NC}"
echo ""

# Step 4: Start rustfs server
echo -e "${BLUE}[4/7] Starting rustfs S3 server...${NC}"
RUSTFS_PID=$(sh "$SCRIPT_DIR/start-rustfs.sh" | tail -1)
echo -e "${GREEN}✓ Rustfs server started (PID: $RUSTFS_PID)${NC}"
echo ""

# Step 5: Create S3 bucket
echo -e "${BLUE}[5/7] Creating S3 bucket for munki repository...${NC}"
sh "$SCRIPT_DIR/create-s3-bucket.sh" \
    --bucket "munki-repo" \
    --endpoint "http://localhost:9000" \
    --region "us-east-1" 2>&1 | tail -5
echo -e "${GREEN}✓ S3 bucket created/verified${NC}"
echo ""

# Step 6: Run end-to-end test
echo -e "${BLUE}[6/7] Running munkiimport test...${NC}"
sh "$SCRIPT_DIR/test_munkiimport.sh" \
    --repo-url "http://localhost:9000/munki-repo" \
    --plugin "S3Repo" 2>&1

EXIT_CODE=$?
echo ""

# Step 7: Cleanup
echo -e "${BLUE}[7/7] Cleaning up...${NC}"
cleanup
echo -e "${GREEN}✓ Cleanup complete${NC}"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
else
    echo -e "${RED}✗ Test failed with exit code $EXIT_CODE${NC}"
fi

exit $EXIT_CODE
