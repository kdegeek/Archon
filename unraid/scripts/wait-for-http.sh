#!/bin/bash

# wait-for-http.sh - Wait for HTTP service to become available
# Usage: wait-for-http.sh <url> [timeout] [interval]

URL="$1"
TIMEOUT="${2:-120}"  # Default 120 seconds timeout
INTERVAL="${3:-2}"   # Default 2 seconds between checks

if [ -z "$URL" ]; then
    echo "Usage: $0 <url> [timeout] [interval]"
    echo "Example: $0 http://archon-server:8181/health 120 2"
    exit 1
fi

echo "Waiting for $URL to become available (timeout: ${TIMEOUT}s)..."

START_TIME=$(date +%s)

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ $ELAPSED -gt $TIMEOUT ]; then
        echo "ERROR: Timeout after ${TIMEOUT}s waiting for $URL"
        exit 1
    fi
    
    # Try curl first, then wget as fallback
    if command -v curl &> /dev/null; then
        if curl -f -s --max-time 5 "$URL" > /dev/null 2>&1; then
            echo "SUCCESS: $URL is now available (after ${ELAPSED}s)"
            exit 0
        fi
    elif command -v wget &> /dev/null; then
        if wget --timeout=5 --tries=1 -q -O /dev/null "$URL" 2>/dev/null; then
            echo "SUCCESS: $URL is now available (after ${ELAPSED}s)"
            exit 0
        fi
    else
        echo "ERROR: Neither curl nor wget available for HTTP checks"
        exit 1
    fi
    
    echo "Waiting for $URL... (${ELAPSED}s elapsed)"
    sleep $INTERVAL
done