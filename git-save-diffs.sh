#!/bin/bash

# git-save-diffs.sh
# Script to generate diffs for specific source files and save them with line range information
# Usage: ./git-save-diffs.sh <source_filename> [output_format]
# output_format: 1 (comma separated) or 2 (newline separated), default is 1

set -euo pipefail

# Check if source filename is provided
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <source_filename> [output_format]"
    echo "Example: $0 src/main.py"
    echo "Example: $0 src/main.py 1  # comma separated (default)"
    echo "Example: $0 src/main.py 2  # newline separated"
    exit 1
fi

SOURCE_FILE="$1"
OUTPUT_FORMAT="${2:-1}"  # Default to 1 (comma separated)

# Validate output format
if [ "$OUTPUT_FORMAT" != "1" ] && [ "$OUTPUT_FORMAT" != "2" ]; then
    echo "Error: output_format must be 1 (comma separated) or 2 (newline separated)"
    exit 1
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository"
    exit 1
fi

# Check if source file exists
if [ ! -f "$SOURCE_FILE" ]; then
    echo "Error: Source file '$SOURCE_FILE' does not exist"
    exit 1
fi

# Function to get the number of commits in current branch
get_commit_count() {
    git rev-list --count HEAD ^master 2>/dev/null || git rev-list --count HEAD ^main 2>/dev/null || echo "0"
}

# Function to get diff between commits
get_diff() {
    local from_commit="$1"
    local to_commit="$2"
    git diff "$from_commit" "$to_commit" -- "$SOURCE_FILE"
}

# Function to parse diff and extract line ranges
parse_diff_ranges() {
    local diff_content="$1"
    
    # Extract line ranges using sed and awk
    echo "$diff_content" | grep '^@@' | sed 's/^@@ -\([0-9]*\),\([0-9]*\).*/\1-\2/' | awk -F'-' '
    {
        start = $1
        count = $2
        if (count > 0) {
            end = start + count - 1
            printf "%d-%d\n", start, end
        }
    }'
}

# Function to save diff for a specific range
save_diff_for_range() {
    local diff_content="$1"
    local range="$2"
    local filename="$3"
    
    # Extract start and end line numbers
    local start_line=$(echo "$range" | cut -d'-' -f1)
    local end_line=$(echo "$range" | cut -d'-' -f2)
    
    # Extract the specific hunk for this range using sed and awk
    echo "$diff_content" | awk -v start="$start_line" -v end="$end_line" '
    BEGIN {
        in_target_hunk = 0
    }
    /^@@/ {
        # Extract hunk start and count using sed
        hunk_info = $0
        gsub(/.*@@ -/, "", hunk_info)
        gsub(/,.*/, "", hunk_info)
        hunk_start = hunk_info
        
        hunk_info = $0
        gsub(/.*@@ -[0-9]+,/, "", hunk_info)
        gsub(/ .*/, "", hunk_info)
        hunk_count = hunk_info
        
        hunk_end = hunk_start + hunk_count - 1
        
        if (hunk_start <= end && hunk_end >= start) {
            in_target_hunk = 1
            print $0
        } else {
            in_target_hunk = 0
        }
        next
    }
    in_target_hunk { print $0 }
    ' > "$filename"
}

# Main logic
COMMIT_COUNT=$(get_commit_count)

if [ "$COMMIT_COUNT" -eq 1 ]; then
    # First commit in branch - diff against master/main
    echo "First commit in branch, comparing against master/main..."
    DIFF_CONTENT=$(get_diff "master" "HEAD" 2>/dev/null || get_diff "main" "HEAD" 2>/dev/null)
else
    # Not first commit - diff against previous commit
    echo "Comparing against previous commit..."
    DIFF_CONTENT=$(get_diff "HEAD~1" "HEAD")
fi

# Check if there are any changes
if [ -z "$DIFF_CONTENT" ]; then
    echo "No changes found for file '$SOURCE_FILE'"
    exit 0
fi

# Get base filename without path
BASE_FILENAME=$(basename "$SOURCE_FILE")
BASE_DIR=$(dirname "$SOURCE_FILE")

# Parse line ranges from diff
RANGES=$(parse_diff_ranges "$DIFF_CONTENT")

if [ -z "$RANGES" ]; then
    echo "No line ranges found in diff"
    exit 0
fi

# Create output directory if it doesn't exist
OUTPUT_DIR="$BASE_DIR"
mkdir -p "$OUTPUT_DIR"

# Process each range and save separate diff files
SAVED_FILES=()

# Process ranges using a temporary file to avoid subshell issues
TEMP_RANGES=$(mktemp)
echo "$RANGES" > "$TEMP_RANGES"

while IFS= read -r range; do
    if [ -n "$range" ]; then
        OUTPUT_FILE="$OUTPUT_DIR/${BASE_FILENAME}.${range}.diff"
        save_diff_for_range "$DIFF_CONTENT" "$range" "$OUTPUT_FILE"
        
        # Check if file was created and has content
        if [ -s "$OUTPUT_FILE" ]; then
            SAVED_FILES+=("$OUTPUT_FILE")
            echo "Saved diff for range $range: $OUTPUT_FILE"
        else
            rm -f "$OUTPUT_FILE"
        fi
    fi
done < "$TEMP_RANGES"

rm -f "$TEMP_RANGES"

# Output saved files based on format
if [ ${#SAVED_FILES[@]} -gt 0 ]; then
    if [ "$OUTPUT_FORMAT" = "1" ]; then
        # Comma separated
        printf '%s\n' "$(IFS=','; echo "${SAVED_FILES[*]}")"
    else
        # Newline separated
        printf '%s\n' "${SAVED_FILES[@]}"
    fi
else
    echo "No diff files were saved"
fi