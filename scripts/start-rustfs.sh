#!/bin/bash
# Start rustfs S3-compatible server and expose the PID

set -e

# Parse arguments
STORAGE_DIR="${HOME}/.s3repo-test-buckets"
ACCESS_KEY="blah"
SECRET_KEY="blah"
PORT="9000"

while [[ $# -gt 0 ]]; do
    case $1 in
        --dir)
            STORAGE_DIR="$2"
            shift 2
            ;;
        --access-key)
            ACCESS_KEY="$2"
            shift 2
            ;;
        --secret-key)
            SECRET_KEY="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dir DIR              Storage directory for rustfs (default: ~/.s3repo-test-buckets)"
            echo "  --access-key KEY       S3 access key (default: blah)"
            echo "  --secret-key KEY       S3 secret key (default: blah)"
            echo "  --port PORT            Server port (default: 9000)"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if rustfs is available
if ! command -v rustfs &> /dev/null; then
    echo "❌ Error: rustfs not found in PATH"
    exit 1
fi

# Create storage directory
mkdir -p "$STORAGE_DIR"

# Start rustfs server in background
echo "Starting rustfs server..."
echo "  Storage: $STORAGE_DIR"
echo "  Port: $PORT"
echo "  Endpoint: http://localhost:$PORT"

rustfs server "$STORAGE_DIR" \
    --console-enable \
    --access-key="$ACCESS_KEY" \
    --secret-key="$SECRET_KEY" \
    --port="$PORT" &

RUSTFS_PID=$!

# Wait for server to start
echo "Waiting for rustfs server to be ready..."
sleep 2

# Check if server is running
if ! kill -0 "$RUSTFS_PID" 2>/dev/null; then
    echo "❌ Error: rustfs server failed to start"
    exit 1
fi

echo "✓ rustfs server started (PID: $RUSTFS_PID)"
echo "$RUSTFS_PID"
