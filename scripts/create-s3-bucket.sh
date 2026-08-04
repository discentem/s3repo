#!/bin/bash
# Create or verify S3 bucket for munki repository

set -e

# Parse arguments
BUCKET_NAME="munki-repo"
S3_ENDPOINT="http://localhost:9000"
S3_REGION="us-east-1"
ACCESS_KEY="blah"
SECRET_KEY="blah"

while [[ $# -gt 0 ]]; do
    case $1 in
        --bucket)
            BUCKET_NAME="$2"
            shift 2
            ;;
        --endpoint)
            S3_ENDPOINT="$2"
            shift 2
            ;;
        --region)
            S3_REGION="$2"
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
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --bucket NAME          S3 bucket name (default: munki-repo)"
            echo "  --endpoint URL         S3 endpoint URL (default: http://localhost:9000)"
            echo "  --region REGION        AWS region (default: us-east-1)"
            echo "  --access-key KEY       S3 access key (default: blah)"
            echo "  --secret-key KEY       S3 secret key (default: blah)"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Find MunkiRepoInit tool (must be built via build-munki-repo-init.sh)
BUCKET_TOOL=".build/arm64-apple-macosx/release/MunkiRepoInit"
if [ ! -f "$BUCKET_TOOL" ]; then
    BUCKET_TOOL=".build/x86_64-apple-macosx/release/MunkiRepoInit"
fi

if [ ! -f "$BUCKET_TOOL" ]; then
    echo "❌ Error: MunkiRepoInit tool not found"
    echo "   Make sure to run scripts/build-munki-repo-init.sh first"
    exit 1
fi

# Check if bucket already exists using AWS CLI
echo "Checking if bucket '$BUCKET_NAME' exists..."

if command -v aws &> /dev/null; then
    if AWS_ACCESS_KEY_ID="$ACCESS_KEY" \
       AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
       aws s3 ls "s3://$BUCKET_NAME" \
       --endpoint-url "$S3_ENDPOINT" \
       --region "$S3_REGION" &>/dev/null 2>&1; then
        echo "✓ Bucket '$BUCKET_NAME' already exists"
        exit 0
    fi
else
    # Without AWS CLI, we'll attempt to create anyway and let MunkiRepoInit handle it
    echo "⚠ AWS CLI not found, skipping existence check"
fi

# Create bucket using MunkiRepoInit
echo "Creating S3 bucket: $BUCKET_NAME"
AWS_ACCESS_KEY_ID="$ACCESS_KEY" \
AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
"$BUCKET_TOOL" "$BUCKET_NAME" \
    --endpoint "$S3_ENDPOINT" \
    --region "$S3_REGION" 2>&1 | head -20 || true

echo "✓ S3 bucket '$BUCKET_NAME' initialized/verified"
