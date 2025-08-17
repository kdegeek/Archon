#!/bin/sh
# wait-for-http.sh - Wait for an HTTP service to be available
# POSIX-compliant shell script

set -e

HOST="${1:-localhost}"
PORT="${2:-80}"
TIMEOUT="${3:-30}"
PROTOCOL="${4:-http}"

if [ -z "$HOST" ] || [ -z "$PORT" ]; then
    echo "Usage: $0 host port [timeout] [protocol]"
    exit 1
fi

echo "Waiting for $PROTOCOL://$HOST:$PORT to be available..."

START_TIME=$(date +%s)
END_TIME=$((START_TIME + TIMEOUT))

while true; do
    CURRENT_TIME=$(date +%s)
    
    if [ "$CURRENT_TIME" -ge "$END_TIME" ]; then
        echo "Timeout: $PROTOCOL://$HOST:$PORT did not become available within $TIMEOUT seconds"
        exit 1
    fi
    
    # Try to connect using available tools
    if command -v curl >/dev/null 2>&1; then
        if curl -fsS "$PROTOCOL://$HOST:$PORT/" >/dev/null 2>&1; then
            echo "$PROTOCOL://$HOST:$PORT is available"
            exit 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget --spider -q "$PROTOCOL://$HOST:$PORT/" 2>/dev/null; then
            echo "$PROTOCOL://$HOST:$PORT is available"
            exit 0
        fi
    elif command -v nc >/dev/null 2>&1; then
        if nc -z "$HOST" "$PORT" 2>/dev/null; then
            echo "$PROTOCOL://$HOST:$PORT is available (TCP connection successful)"
            exit 0
        fi
    else
        echo "Error: No suitable tool found (curl, wget, or nc required)"
        exit 1
    fi
    
    sleep 1
done