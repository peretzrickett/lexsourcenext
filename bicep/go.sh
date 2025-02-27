#!/bin/bash

# File paths
TEMPLATE_FILE="main.bicep"
PARAMS_FILE="clients.json"
OUTPUT_FILE="errors.json"
WINNER_SOUND="dingding.mp3"  # Example winner sound (adjust path)
LOSER_SOUND="nocigar.mp3"  # Example loser sound (adjust path)

# Function to play sound (uses paplay for PulseAudio, fall back to play for SoX)
play_sound() {
    local sound_file=$1
    if command -v paplay &> /dev/null; then
        paplay "$sound_file" 2>/dev/null || echo "Sound playback failed (paplay)"
    elif command -v play &> /dev/null; then
        play "$sound_file" 2>/dev/null || echo "Sound playback failed (play)"
    else
        echo "Sound playback not supported (install paplay or sox)"
    fi
}

# Run Azure deployment and capture output
echo "Deploying Azure resources with $TEMPLATE_FILE and $PARAMS_FILE..."
DEPLOYMENT_OUTPUT=$(az deployment sub create --location eastus --template-file "$TEMPLATE_FILE" --parameters "@$PARAMS_FILE" 2>&1)

# Check deployment status
if echo "$DEPLOYMENT_OUTPUT" | grep -q '"status": "Succeeded"'; then
    echo "Deployment succeeded!"
    play_sound "$WINNER_SOUND"
else
    echo "Deployment failed!"
    play_sound "$LOSER_SOUND"

    # Extract and format JSON error output into errors.json using jq
    echo "$DEPLOYMENT_OUTPUT" | jq '.' > "$OUTPUT_FILE"
    if [ $? -eq 0 ]; then
        echo "Error details saved to $OUTPUT_FILE"
    else
        echo "Failed to format error output. Raw output:"
        echo "$DEPLOYMENT_OUTPUT" > "$OUTPUT_FILE"
    fi
fi