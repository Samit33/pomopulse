#!/bin/bash

# PomoPulse Build Script
# Requires Connect IQ SDK to be installed

set -e

# Configuration
DEVICE="${1:-fr255}"
OUTPUT_DIR="bin"
OUTPUT_FILE="$OUTPUT_DIR/PomoPulse.prg"
DEV_KEY="${DEV_KEY:-$HOME/garmin-keys/developer.der}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "PomoPulse Build Script"
echo "======================"

# Check for monkeyc
if ! command -v monkeyc &> /dev/null; then
    echo -e "${RED}Error: monkeyc not found in PATH${NC}"
    echo ""
    echo "Please install the Connect IQ SDK:"
    echo "  1. Download from: https://developer.garmin.com/connect-iq/sdk/"
    echo "  2. Extract to ~/connectiq-sdk"
    echo "  3. Add to PATH: export PATH=\$PATH:~/connectiq-sdk/bin"
    echo "  4. Generate developer key: ~/connectiq-sdk/bin/generateKey ~/garmin-keys/developer.der"
    exit 1
fi

# Check for developer key
if [ ! -f "$DEV_KEY" ]; then
    echo -e "${YELLOW}Warning: Developer key not found at $DEV_KEY${NC}"
    echo "Generate one with: monkeyc's generateKey tool"
    echo ""
    read -p "Continue without signing? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    DEV_KEY=""
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Build command
echo -e "${GREEN}Building for $DEVICE...${NC}"

BUILD_CMD="monkeyc -d $DEVICE -f monkey.jungle -o $OUTPUT_FILE -l 3 --warn"
if [ -n "$DEV_KEY" ]; then
    BUILD_CMD="$BUILD_CMD -y $DEV_KEY"
fi

echo "Running: $BUILD_CMD"
$BUILD_CMD

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Build successful!${NC}"
    echo "Output: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi
