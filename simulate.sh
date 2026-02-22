#!/bin/bash
# PomoPulse simulator launcher

export PATH="$HOME/jre21/bin:$HOME/connectiq-sdk/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/libs:$LD_LIBRARY_PATH"

PRG="$(dirname "$0")/bin/PomoPulse.prg"
KEY="$HOME/garmin-keys/developer.der"

# Kill any existing simulator
pkill -f "simulator-8.4.1" 2>/dev/null
sleep 1

# Build
echo "Building..."
monkeyc -d fr255 -f "$(dirname "$0")/monkey.jungle" -o "$PRG" -y "$KEY" -l 0
if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi
echo "Build OK: $(du -sh "$PRG" | cut -f1)"

# Launch simulator
echo "Starting simulator..."
~/.Garmin/ConnectIQ/AppImages/simulator-8.4.1.AppImage &
SIM_PID=$!
echo "Simulator PID: $SIM_PID"

# Wait for simulator to be ready
echo "Waiting for simulator to initialize..."
for i in $(seq 1 15); do
    sleep 1
    if python3 -c "import socket; s=socket.create_connection(('localhost',1234),0.5); s.close()" 2>/dev/null; then
        echo "Simulator ready (${i}s)"
        break
    fi
    echo "  Waiting... ${i}s"
done

sleep 2

# Push app
echo "Pushing app to simulator..."
monkeydo "$PRG" fr255
echo "Done. Check your display for the simulator window."
