#!/bin/sh
# Frontend entrypoint script to inject runtime configuration

set -e

# Create config.js with runtime environment variables
cat > /usr/share/nginx/html/config.js <<EOF
window.RUNTIME_CONFIG = {
  VITE_API_URL: "${VITE_API_URL:-http://localhost:8181}",
  VITE_MCP_URL: "${VITE_MCP_URL:-http://localhost:8051}",
  VITE_AGENTS_URL: "${VITE_AGENTS_URL:-http://localhost:8052}"
};
EOF

echo "Runtime configuration written to /usr/share/nginx/html/config.js"
echo "VITE_API_URL: ${VITE_API_URL:-http://localhost:8181}"
echo "VITE_MCP_URL: ${VITE_MCP_URL:-http://localhost:8051}"
echo "VITE_AGENTS_URL: ${VITE_AGENTS_URL:-http://localhost:8052}"

# Replace placeholders in built files if they exist
# This handles cases where the app was built with placeholder values
find /usr/share/nginx/html -type f -name "*.js" -o -name "*.html" | while read file; do
  if grep -q "__VITE_API_URL__" "$file" 2>/dev/null; then
    sed -i "s|__VITE_API_URL__|${VITE_API_URL:-http://localhost:8181}|g" "$file"
    sed -i "s|__VITE_MCP_URL__|${VITE_MCP_URL:-http://localhost:8051}|g" "$file"
    sed -i "s|__VITE_AGENTS_URL__|${VITE_AGENTS_URL:-http://localhost:8052}|g" "$file"
    echo "Updated placeholders in: $file"
  fi
done

# Execute the original nginx command
exec "$@"