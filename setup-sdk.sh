#!/bin/bash

# Connect IQ SDK Setup Script for WSL/Linux
# Downloads and configures the Garmin Connect IQ SDK

set -e

SDK_VERSION="7.3.1"
SDK_DIR="$HOME/connectiq-sdk"
KEY_DIR="$HOME/garmin-keys"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Connect IQ SDK Setup"
echo "===================="

# Check for Java
if ! command -v java &> /dev/null; then
    echo -e "${RED}Java not found. Installing OpenJDK 11...${NC}"
    sudo apt update && sudo apt install -y openjdk-11-jdk
fi

java -version

# Check if SDK already exists
if [ -d "$SDK_DIR" ] && [ -f "$SDK_DIR/bin/monkeyc" ]; then
    echo -e "${GREEN}SDK already installed at $SDK_DIR${NC}"
else
    echo -e "${YELLOW}SDK not found. Please download manually:${NC}"
    echo ""
    echo "1. Visit: https://developer.garmin.com/connect-iq/sdk/"
    echo "2. Download the Linux SDK (connectiq-sdk-lin-*.zip)"
    echo "3. Extract to: $SDK_DIR"
    echo ""
    echo "Or use the SDK Manager GUI if you have X11 forwarding set up."
    echo ""
    read -p "Press Enter once SDK is extracted to $SDK_DIR..."
fi

# Verify SDK installation
if [ ! -f "$SDK_DIR/bin/monkeyc" ]; then
    echo -e "${RED}monkeyc not found in $SDK_DIR/bin/${NC}"
    echo "Please ensure the SDK is properly extracted."
    exit 1
fi

# Add to PATH
if ! grep -q "connectiq-sdk" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Garmin Connect IQ SDK" >> ~/.bashrc
    echo "export PATH=\$PATH:$SDK_DIR/bin" >> ~/.bashrc
    echo -e "${GREEN}Added SDK to PATH in ~/.bashrc${NC}"
fi

export PATH="$PATH:$SDK_DIR/bin"

# Generate developer key
if [ ! -f "$KEY_DIR/developer.der" ]; then
    echo -e "${YELLOW}Generating developer key...${NC}"
    mkdir -p "$KEY_DIR"
    "$SDK_DIR/bin/generateKey" "$KEY_DIR/developer.der"
    echo -e "${GREEN}Developer key created at $KEY_DIR/developer.der${NC}"
else
    echo -e "${GREEN}Developer key already exists at $KEY_DIR/developer.der${NC}"
fi

# Verify
echo ""
echo "Verification:"
echo "============="
monkeyc --version
echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "To build PomoPulse:"
echo "  cd $(dirname "$0")"
echo "  ./build.sh"
echo ""
echo "Or manually:"
echo "  monkeyc -d fr255 -f monkey.jungle -o bin/PomoPulse.prg -y $KEY_DIR/developer.der"
