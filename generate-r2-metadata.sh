#!/bin/bash
# A script to generate metadata files (dataset.uri and dataset.md5) for an R2 bucket dataset.
# The script will:
# 1. Generate dataset.uri with the base URL
# 2. Generate dataset.md5 with checksums of all files
# 3. Place metadata files in the metadata directory

# Function to show help
show_help() {
    cat << EOF
R2 Metadata Generator - Generate metadata files for Cloudflare R2 bucket datasets and optionally upload them to the bucket.

USAGE: bash generate-r2-metadata.sh [-h]

OPTIONS:
    -h    Show this help message and exit

DESCRIPTION:
    This script generates two metadata files for datasets stored in Cloudflare R2 buckets:
    
    1. dataset.uri - Contains the base URL for accessing the dataset files
    2. dataset.md5 - Contains MD5 checksums for all files in the dataset
    
    The script determines if a path is a file or a directory based on whether it
    ends with a trailing slash. Always use a trailing slash for directories.
    
    The script will prompt you for the following information:
    - Bucket name and path within the bucket
    - Public URL for the bucket (without https://)
    - Dataset name (used for naming the metadata files)
    - R2 Access Key and Secret Key (for reading files and optionally uploading metadata)

EXAMPLES:
    # Generate metadata files interactively
    bash generate-r2-metadata.sh
    
    # Show help
    bash generate-r2-metadata.sh -h

INPUT PROMPTS:
    Bucket Path: Enter the bucket name and optional path. Use a trailing slash
                 '/' to indicate a directory.
                 Examples: 'my-bucket/data/dataset-dir/' (directory)
                           'my-bucket/data/individual-file.tsv' (file)
                 
    Bucket URL:  Enter the public URL without 'https://' prefix
                 Example: 'inference-private.mlcommons-storage.org'
                 
    Dataset Name: Enter a name for the dataset (used for metadata filenames)
                  Example: 'llama2' creates 'llama2.uri' and 'llama2.md5'
                  
    Credentials: R2 Access Key and Secret Key with read access to the bucket
                 Write access is only needed if you choose to upload metadata files

OUTPUT:
    The script creates a 'metadata/' directory containing:
    - {dataset-name}.uri - Base URL for the dataset
    - {dataset-name}.md5 - MD5 checksums for all files
    
    Optionally uploads these files to the bucket's metadata directory.
    The script will ask for confirmation before uploading.

REQUIREMENTS:
    - rclone 1.60.0 or higher (for accessing Cloudflare R2)
    - R2 credentials with read access to the target bucket
    - Write access to R2 bucket (only if uploading metadata files)

EOF
}

# Parse command line options
while getopts "h" opt; do
    case $opt in
        h)
            show_help
            exit 0
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            echo "Use -h for help" >&2
            exit 1
            ;;
    esac
done

# Fixed R2 endpoint for MLCommons R2
ENDPOINT="https://c2686074cb2caf5cbaf6d134bdba8b47.r2.cloudflarestorage.com"

# Generate a unique temporary remote name
TMP_REMOTE="temp_r2_$(date +%s%N)_$RANDOM"

# Cleanup function to remove temporary rclone configuration
cleanup() {
    if [[ -n "$TMP_REMOTE" ]] && rclone config show "$TMP_REMOTE" &> /dev/null; then
        echo "Cleaning up temporary rclone configuration: $TMP_REMOTE"
        rclone config delete "$TMP_REMOTE" 2>/dev/null || true
    fi
}

# Set trap to run cleanup on exit
trap cleanup EXIT

# Function to check rclone installation and version
check_rclone() {
    echo "Checking rclone..."
    
    # Get rclone version (this also checks if rclone is installed)
    local version_output
    if ! version_output=$(rclone version 2>&1); then
        echo "Error: rclone is required but not found or failed to run." >&2
        echo "Please install rclone version 1.60.0 or higher." >&2
        echo "Visit: https://rclone.org/install/" >&2
        exit 1
    fi
    
    # Extract version number from first line using regex
    local first_line
    first_line=$(echo "$version_output" | head -n1)
    
    echo "Found: $first_line"
    
    if [[ $first_line =~ rclone[[:space:]]+v([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local patch="${BASH_REMATCH[3]}"
        
        # Check if version is 1.60.0 or higher
        if [ "$major" -lt 1 ] || ([ "$major" -eq 1 ] && [ "$minor" -lt 60 ]); then
            echo "Error: rclone version ${major}.${minor}.${patch} is too old." >&2
            echo "Cloudflare R2 support requires rclone version 1.60.0 or higher." >&2
            echo "Please update rclone: https://rclone.org/install/" >&2
            exit 1
        fi
        
        echo "rclone version check passed."
    else
        echo "Warning: Could not parse version number from rclone output." >&2
        echo "Proceeding anyway, but ensure you have rclone 1.60.0 or higher for R2 support." >&2
    fi
}

# Check dependencies
check_rclone

# Prompt for bucket name/path
read -p "Enter bucket name and path. Use a trailing slash for directories (e.g., 'bucket/path/dir/'): " DATASET_PATH

# Remove trailing slash if present to normalize the path
DATASET_PATH="${DATASET_PATH%/}"

# Extract bucket name and subpath
BUCKET_NAME=$(echo "$DATASET_PATH" | cut -d'/' -f1)
if [[ "$DATASET_PATH" == */* ]]; then
    BUCKET_SUBPATH=$(echo "$DATASET_PATH" | cut -d'/' -f2-)
else
    BUCKET_SUBPATH=""
fi

# Prompt for bucket URL without protocol (HTTPS will be prepended)
read -p "Enter bucket URL without 'https://' (e.g., inference-private.mlcommons-storage.org): " URL

# Prompt for dataset name
read -p "Enter dataset name (this will be used as the name of the metadata files): " DATASET_NAME

# Prompt for credentials (keys will be hidden in the terminal)
read -p "Enter your R2 Access Key (write access required for uploading metadata files): " -s ACCESS_KEY
echo
read -p "Enter your R2 Secret Key (write access required for uploading metadata files): " -s SECRET_KEY
echo

# Create temporary rclone remote configuration using provided credentials.
echo "Creating temporary rclone configuration..."
rclone config create "$TMP_REMOTE" s3 \
  provider="Cloudflare" \
  access_key_id="$ACCESS_KEY" \
  secret_access_key="$SECRET_KEY" \
  endpoint="$ENDPOINT" \
  no_check_bucket=true \
  --non-interactive

# Verify remote configuration
if ! rclone config show "$TMP_REMOTE" &> /dev/null; then
  echo "Error: Failed to create temporary rclone configuration."
  exit 1
fi

# Test bucket access by attempting to list the bucket contents
echo "Testing bucket access..."
if ! rclone lsd "${TMP_REMOTE}:${DATASET_PATH}" > /dev/null 2>&1; then
  echo "Error: Cannot access bucket or path '${DATASET_PATH}'" >&2
  echo "This could be due to:" >&2
  echo "  - Invalid credentials" >&2
  echo "  - Insufficient permissions" >&2
  echo "  - Incorrect bucket name or path" >&2
  echo "  - Network connectivity issues" >&2
  exit 1
fi

echo "Bucket access verified successfully."

# Create metadata directory if it doesn't exist
METADATA_DIR="metadata"
mkdir -p "$METADATA_DIR"

# Check if the path is a file or a directory based on the presence of a trailing slash.
# If no trailing slash, it is assumed to be a file.
if [[ "$BUCKET_SUBPATH" == */ || -z "$BUCKET_SUBPATH" ]]; then
  uri_path="${BUCKET_SUBPATH%/}"
  echo "The provided path is a directory. The URI will point to the directory itself."
else
  uri_path=$(dirname "${BUCKET_SUBPATH%/}")
  echo "The provided path is a file. The URI will point to its parent directory."
fi

# Construct the final URI.
if [[ -z "$uri_path" || "$uri_path" == "." ]]; then
  URI="https://${URL}"
else
  URI="https://${URL}/${uri_path%/}"
fi

# Generate dataset.uri file
URI_FILE="${METADATA_DIR}/${DATASET_NAME}.uri"
echo "Generating URI file: ${URI_FILE}"
echo "$URI" > "$URI_FILE"

# Generate dataset.md5 file
MD5_FILE="${METADATA_DIR}/${DATASET_NAME}.md5"
echo "Generating MD5 file: ${MD5_FILE}"
echo "This may take a while for large datasets..."

if ! rclone md5sum "${TMP_REMOTE}:${DATASET_PATH}" | sort > "$MD5_FILE"; then
    echo "Error: Failed to generate MD5 list for dataset '${DATASET_NAME}'" >&2
    echo "This could be due to:" >&2
    echo "  - Invalid credentials" >&2
    echo "  - Insufficient permissions" >&2
    echo "  - Incorrect bucket name or path" >&2
    echo "  - Network connectivity issues" >&2
    rm -f "$MD5_FILE"  # Clean up empty file
    rm -f "$URI_FILE"  # Clean up uri file too
    exit 1
fi

# Verify that the md5 file is not empty
if [ ! -s "$MD5_FILE" ]; then
  echo "Error: Generated checksums file is empty" >&2
  echo "This indicates no files were found in the specified bucket path: '${DATASET_PATH}'" >&2
  rm -f "$MD5_FILE"  # Clean up empty file
  rm -f "$URI_FILE"  # Clean up uri file too
  exit 1
fi

echo "Successfully computed checksums for $(wc -l < "$MD5_FILE") files."

# Get dataset size information
echo "Getting dataset size information..."
if size_json=$(rclone size --json "${TMP_REMOTE}:${DATASET_PATH}" 2>/dev/null); then
    # Parse JSON output
    file_count=$(echo "$size_json" | grep -o '"count":[0-9]*' | cut -d':' -f2)
    total_bytes=$(echo "$size_json" | grep -o '"bytes":[0-9]*' | cut -d':' -f2)
    
    if [[ -n "$file_count" && -n "$total_bytes" ]]; then
        # Use numfmt to format bytes in human-readable format (SI units: KB, MB, GB, TB)
        if command -v numfmt &> /dev/null; then
            formatted_size=$(numfmt --to=si "$total_bytes")
            echo "Dataset contains $file_count files with a total size of $formatted_size"
        else
            echo "Dataset contains $file_count files with a total size of $total_bytes bytes"
        fi
    else
        echo "Warning: Could not parse size information from rclone output" >&2
    fi
else
    echo "Warning: Could not retrieve dataset size information" >&2
fi

echo "Success! Generated metadata files in ${METADATA_DIR}/"
echo "Files created:"
echo "- ${METADATA_DIR}/${DATASET_NAME}.uri"
echo "- ${METADATA_DIR}/${DATASET_NAME}.md5"

# Ask if user wants to upload the metadata files
read -p "Do you want to upload these metadata files to the bucket? (y/n): " UPLOAD_CHOICE

if [[ "$UPLOAD_CHOICE" =~ ^[Yy]$ ]]; then
    # Check if files already exist in the bucket's metadata directory
    METADATA_BUCKET_PATH="metadata"

    # Check for existing files using the existing temporary remote
    URL_EXISTS=$(rclone ls "${TMP_REMOTE}:${BUCKET_NAME}/${METADATA_BUCKET_PATH}/${DATASET_NAME}.uri" 2>/dev/null)
    MD5_EXISTS=$(rclone ls "${TMP_REMOTE}:${BUCKET_NAME}/${METADATA_BUCKET_PATH}/${DATASET_NAME}.md5" 2>/dev/null)

    if [[ -n "$URL_EXISTS" || -n "$MD5_EXISTS" ]]; then
        echo "Warning: Metadata files already exist in the bucket:"
        [[ -n "$URL_EXISTS" ]] && echo "- ${DATASET_NAME}.uri"
        [[ -n "$MD5_EXISTS" ]] && echo "- ${DATASET_NAME}.md5"
        
        read -p "Do you want to replace the existing files? (y/n): " REPLACE_CHOICE
        if [[ ! "$REPLACE_CHOICE" =~ ^[Yy]$ ]]; then
            echo "Upload cancelled."
            exit 0
        fi
    fi

    # Create metadata directory in bucket if it doesn't exist
    echo "Creating metadata directory in bucket if it doesn't exist..."
    rclone mkdir "${TMP_REMOTE}:${BUCKET_NAME}/${METADATA_BUCKET_PATH}" 2>/dev/null || true

    # Upload the files
    echo "Uploading metadata files to bucket..."
    rclone copy "$URI_FILE" "${TMP_REMOTE}:${BUCKET_NAME}/${METADATA_BUCKET_PATH}/" --header-upload "Content-Type: text/plain; charset=utf-8" || {
        echo "Error: Failed to upload ${DATASET_NAME}.uri" >&2
        exit 1
    }
    
    rclone copy "$MD5_FILE" "${TMP_REMOTE}:${BUCKET_NAME}/${METADATA_BUCKET_PATH}/" --header-upload "Content-Type: text/plain; charset=utf-8" || {
        echo "Error: Failed to upload ${DATASET_NAME}.md5" >&2
        exit 1
    }

    echo "Successfully uploaded metadata files to ${BUCKET_NAME}/${METADATA_BUCKET_PATH}/"
fi
