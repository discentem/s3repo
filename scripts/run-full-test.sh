#!/bin/bash
# Full end-to-end test script: build → package → install → test
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KEEP_RUSTFS_ALIVE="${1:-false}"  # Pass 'true' to keep rustfs server alive after test

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== S3Repo Full End-to-End Test ===${NC}"
echo "Keep rustfs server alive: $KEEP_RUSTFS_ALIVE"
echo ""

# Step 1: Build plugin package (includes Swift build)
echo -e "${BLUE}[1/3] Building plugin package...${NC}"
cd "$PROJECT_ROOT"
sh "$SCRIPT_DIR/build-plugin-package.sh" 2>&1 | tail -10
echo -e "${GREEN}✓ Plugin package built${NC}"
echo ""

# Step 2: Install plugin package
echo -e "${BLUE}[2/3] Installing plugin package...${NC}"
sudo sh "$SCRIPT_DIR/install-plugin-package.sh" 2>&1 | tail -5
echo -e "${GREEN}✓ Plugin installed${NC}"
echo ""

# Step 3: Run end-to-end test
echo -e "${BLUE}[3/3] Running end-to-end test with server setup...${NC}"
sh "$SCRIPT_DIR/test_munkiimport.sh" "${2:-/Applications/Ghostty.app}" "http://localhost:9000/munki-repo" "S3Repo" "true" "$KEEP_RUSTFS_ALIVE" 2>&1

EXIT_CODE=$?
echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
else
    echo -e "${RED}✗ Test failed with exit code $EXIT_CODE${NC}"
fi

exit $EXIT_CODE
