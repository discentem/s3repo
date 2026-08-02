#!/bin/bash
set -e

# Build and install
echo "Building..."
sh scripts/build-plugin-package.sh > /dev/null 2>&1

echo "Installing..."
sudo sh scripts/install-plugin-package.sh > /dev/null 2>&1

# Test with timeout
echo "Testing munkiimport with 5 second timeout..."
timeout 5 munkiimport /Applications/Ghostty.app --plugin S3Repo -vvv 2>&1 | grep -A 2 "Analyzing installer item" || echo "TIMEOUT OR ERROR"
echo "Test completed"
