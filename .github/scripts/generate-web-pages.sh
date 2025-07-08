#!/bin/bash
set -euo pipefail

echo "🔄 Generating index.html files from template..."
TEMPLATE_FILE="templates/template-index.html"
DOWNLOADER_SCRIPT_URL="https://raw.githubusercontent.com/mlcommons/r2-downloader/refs/heads/main/mlc-r2-downloader.sh"

# Helper function for multiline search and replace
# Uses a simpler approach to avoid escaping issues
safe_replace() {
    local placeholder="$1"
    local replacement_file="$2"
    local target_file="$3"
    
    # Use a unique temporary marker that won't conflict with content
    local temp_marker="__TEMP_REPLACEMENT_MARKER_$$__"
    
    # First, replace the placeholder with our temporary marker
    sed "s|$placeholder|$temp_marker|g" "$target_file" > "$target_file.tmp"
    
    # Then use awk to replace the temporary marker with the file content
    awk -v marker="$temp_marker" '
        FNR==NR {
            # Read the replacement file content
            content = content ? content "\n" $0 : $0
            next
        }
        {
            # Replace the temporary marker with the content
            gsub(marker, content)
            print
        }
    ' "$replacement_file" "$target_file.tmp" > "$target_file"
    
    # Clean up temporary file
    rm "$target_file.tmp"
}

# Helper to HTML-escape special characters
html_escape() {
    echo "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Find and process all metadata.json files (excluding central)
find . -name "metadata.json" -not -path "./central/*" | while read -r metadata_file; do
    dir=$(dirname "$metadata_file")
    folder_name=$(basename "$dir")
    output_html_file="${dir}/index.html"
    
    echo "  - Processing: ${folder_name}"
    
    # --- Read metadata from JSON file ---
    domain=$(jq -r '.domain' "$metadata_file")
    page_title=$(jq -r '.title' "$metadata_file")
    license_notice=$(jq -r '.license_notice' "$metadata_file")
    
    if [ -z "$domain" ] || [ "$domain" == "null" ]; then
        echo "    - ⚠️ Warning: Skipping '${folder_name}' because 'domain' is missing in metadata.json"
        continue
    fi
    
    # --- Create index.html from template ---
    cp "$TEMPLATE_FILE" "$output_html_file"
    
    # --- Fill in template placeholders ---
    
    # 1. Page Title and H1
    sed -i "s|__TITLE__|${page_title}|g" "$output_html_file"
    
    # 2. License Notice
    license_block_file=$(mktemp)
    if [ -n "$license_notice" ] && [ "$license_notice" != "null" ]; then
        echo "<div class=\"alert alert-info\"><strong>Licensing Notice:</strong> ${license_notice}</div>" > "$license_block_file"
    fi
    safe_replace "__LICENSE_NOTICE_BLOCK__" "$license_block_file" "$output_html_file"
    rm "$license_block_file"
    
    # 3. Dataset Sections
    dataset_sections_file=$(mktemp)
    
    # Get categories and process them one by one
    while IFS= read -r category; do
        cat_heading=$(html_escape "$category")
        echo "<h3>$cat_heading</h3>" >> "$dataset_sections_file"
        
        # Get all datasets for this category and process them
        while IFS= read -r dataset_json; do
            name=$(echo "$dataset_json" | jq -r '.name')
            raw_title=$(echo "$dataset_json" | jq -r '.title')
            raw_description=$(echo "$dataset_json" | jq -r '.description')
            size=$(echo "$dataset_json" | jq -r '.size')
            destination=$(echo "$dataset_json" | jq -r '.destination')
            
            title=$(html_escape "$raw_title")
            description=$(html_escape "$raw_description")
            
            full_desc="$description"
            if [ -n "$size" ] && [ "$size" != "null" ] && [ "$size" != "0B" ]; then
                full_desc+=" (~${size})"
            fi
            
            command="bash <(curl -s ${DOWNLOADER_SCRIPT_URL})"
            if [ -n "$destination" ] && [ "$destination" != "null" ]; then
                command+=" -d ${destination}"
            fi
            command+=" https://${domain}/metadata/${name}.uri"
            
            # Append the HTML block for the dataset
            cat >> "$dataset_sections_file" <<EOF
<div class="dataset-section">
    <h3 class="dataset-title">${title}</h3>
    <p class="dataset-description">${full_desc}</p>
    <div class="command-section">
        <div class="code-block">
            <code>${command}</code>
        </div>
    </div>
</div>
EOF
        done < <(jq -c ".datasets[\"$category\"][]" "$metadata_file")
    done < <(jq -r '.datasets | keys[]' "$metadata_file")
    
    safe_replace "__DATASET_SECTIONS__" "$dataset_sections_file" "$output_html_file"
    rm "$dataset_sections_file"
done

echo "✅ Generation of index.html files complete." 