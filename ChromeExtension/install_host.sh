#!/bin/bash
# Pipeline — Install Chrome Native Messaging Host manifest
#
# Usage: ./install_host.sh <extension_id> [--dev]
#
# Arguments:
#   extension_id  The Chrome extension ID from chrome://extensions
#   --dev         Use the Xcode DerivedData build path instead of /Applications

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_NAME="io.github.digitaltracer.pipeline"
TARGET_DIR="${HOME}/Library/Application Support/Google/Chrome/NativeMessagingHosts"

if [ $# -lt 1 ] || [ "$1" = "--help" ]; then
    echo "Usage: ./install_host.sh <extension_id> [--dev]"
    echo ""
    echo "  extension_id  Your Chrome extension ID (from chrome://extensions)"
    echo "  --dev         Use Xcode DerivedData build path (for development)"
    echo ""
    echo "Example:"
    echo "  ./install_host.sh abcdefghijklmnopqrstuvwx --dev"
    exit 1
fi

EXT_ID="$1"
USE_DEV=false

if [ $# -ge 2 ] && [ "$2" = "--dev" ]; then
    USE_DEV=true
fi

# Determine binary path
if [ "$USE_DEV" = true ]; then
    # Prefer the standalone target output. The embedded app copy can be
    # re-signed by Xcode and fail to launch under native messaging.
    HOST_PATH=$(find "${HOME}/Library/Developer/Xcode/DerivedData" -path "*/Pipeline-*/Build/Products/Debug/PipelineNativeHost" -type f 2>/dev/null | head -1)
    if [ -z "$HOST_PATH" ]; then
        # Fallback for older builds that only had the embedded copy.
        HOST_PATH=$(find "${HOME}/Library/Developer/Xcode/DerivedData" -path "*/Pipeline-*/Build/Products/Debug/Pipeline.app/Contents/MacOS/PipelineNativeHost" -type f 2>/dev/null | head -1)
    fi
    if [ -z "$HOST_PATH" ]; then
        echo "Error: Could not find PipelineNativeHost in DerivedData."
        echo "Make sure you've built the Pipeline project in Xcode first."
        exit 1
    fi
    echo "Using development build: ${HOST_PATH}"
else
    HOST_PATH="/Applications/Pipeline.app/Contents/MacOS/PipelineNativeHost"
    if [ ! -f "$HOST_PATH" ]; then
        echo "Warning: ${HOST_PATH} does not exist yet."
        echo "Tip: Use --dev flag to use the Xcode build instead."
    fi
fi

# Create target directory
mkdir -p "${TARGET_DIR}"

MANIFEST_DEST="${TARGET_DIR}/${HOST_NAME}.json"

# Write the manifest
cat > "${MANIFEST_DEST}" << MANIFEST
{
  "name": "io.github.digitaltracer.pipeline",
  "description": "Pipeline — Job Application Tracker native messaging host",
  "path": "${HOST_PATH}",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://${EXT_ID}/"
  ]
}
MANIFEST

echo ""
echo "Installed: ${MANIFEST_DEST}"
echo "Extension ID: ${EXT_ID}"
echo "Host binary: ${HOST_PATH}"
echo ""
echo "Restart Chrome for changes to take effect."
