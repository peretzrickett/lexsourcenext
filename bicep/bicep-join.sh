#!/bin/bash

# Output file name
OUTPUT_FILE="all_bicep.txt"

# Clear the output file if it exists
> "$OUTPUT_FILE"

# Find all .bicep files recursively and concatenate their contents
echo "Joining all .bicep files into $OUTPUT_FILE..."
find . -type f -name "*.bicep" -exec cat {} + >> "$OUTPUT_FILE"

# Add a separator between files for readability
sed -i 's/^\(.\)/\n---\n\1/' "$OUTPUT_FILE"

echo "Done. Output saved to $OUTPUT_FILE"