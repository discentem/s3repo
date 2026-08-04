#!/bin/bash
# Setup S3-compatible munki repository structure using AWS CLI
# Creates bucket and directory structure: catalogs/, manifests/, pkgs/, pkgsinfo/

set -e

# Parse arguments
BUCKET_NAME="munki-repo"
S3_ENDPOINT="http://localhost:9000"
S3_REGION="us-east-1"
ACCESS_KEY="${AWS_ACCESS_KEY_ID:-blah}"
SECRET_KEY="${AWS_SECRET_ACCESS_KEY:-blah}"

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
            echo "Creates S3 bucket and munki repository directory structure"
            echo ""
            echo "Options:"
            echo "  --bucket NAME          S3 bucket name (default: munki-repo)"
            echo "  --endpoint URL         S3 endpoint URL (default: http://localhost:9000)"
            echo "  --region REGION        AWS region (default: us-east-1)"
            echo "  --access-key KEY       S3 access key (default: AWS_ACCESS_KEY_ID env var or 'blah')"
            echo "  --secret-key KEY       S3 secret key (default: AWS_SECRET_ACCESS_KEY env var or 'blah')"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Verify AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo "❌ Error: AWS CLI not found. Please install it."
    exit 1
fi

# Check if bucket already exists
echo "Checking if bucket '$BUCKET_NAME' exists..."
if AWS_ACCESS_KEY_ID="$ACCESS_KEY" \
   AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
   aws s3 ls "s3://$BUCKET_NAME" \
   --endpoint-url "$S3_ENDPOINT" \
   --region "$S3_REGION" &>/dev/null 2>&1; then
    echo "✓ Bucket '$BUCKET_NAME' already exists"
else
    # Create bucket
    echo "Creating S3 bucket: $BUCKET_NAME"
    AWS_ACCESS_KEY_ID="$ACCESS_KEY" \
    AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
    aws s3 mb "s3://$BUCKET_NAME" \
        --endpoint-url "$S3_ENDPOINT" \
        --region "$S3_REGION" || {
        echo "❌ Failed to create bucket"
        exit 1
    }
    echo "✓ Bucket created: $BUCKET_NAME"
fi

# Create directory structure by uploading .keep marker files
DIRECTORIES=("catalogs" "manifests" "pkgs" "pkgsinfo")
for dir in "${DIRECTORIES[@]}"; do
    KEY="$dir/.keep"
    
    # Check if .keep already exists
    if AWS_ACCESS_KEY_ID="$ACCESS_KEY" \
       AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
       aws s3api head-object \
           --bucket "$BUCKET_NAME" \
           --key "$KEY" \
           --endpoint-url "$S3_ENDPOINT" \
           --region "$S3_REGION" &>/dev/null 2>&1; then
        echo "✓ Directory exists: $dir/"
    else
        # Create empty .keep file
        echo -n "" | AWS_ACCESS_KEY_ID="$ACCESS_KEY" \
        AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
        aws s3 cp - "s3://$BUCKET_NAME/$KEY" \
            --endpoint-url "$S3_ENDPOINT" \
            --region "$S3_REGION" || {
            echo "❌ Failed to create directory marker: $dir/.keep"
            exit 1
        }
        echo "✓ Created directory: $dir/"
    fi
done

echo "✓ S3 repository '$BUCKET_NAME' fully initialized"
