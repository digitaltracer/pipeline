#!/bin/bash
# Pipeline — Install Chrome Native Messaging Host manifest
#
# Usage: ./install_host.sh [extension_id]
#
# If no extension_id is provided, the placeholder in the manifest is used as-is.
# For local development, pass the unpacked extension ID shown in chrome://extensions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_NAME="io.github.digitaltracer.pipeline"
MANIFEST_SOURCE="${SCRIPT_DIR}/${HOST_NAME}.json"
TARGET_DIR="${HOME}/Library/Application Support/Google/Chrome/NativeMessagingHosts"

# Create target directory if needed
mkdir -p "${TARGET_DIR}"

MANIFEST_DEST="${TARGET_DIR}/${HOST_NAME}.json"

if [ $# -ge 1 ]; then
    EXT_ID="$1"
    echo "Installing host manifest with extension ID: ${EXT_ID}"
    sed "s/PLACEHOLDER_EXTENSION_ID/${EXT_ID}/g" "${MANIFEST_SOURCE}" > "${MANIFEST_DEST}"
else
    echo "Installing host manifest (placeholder extension ID)"
    cp "${MANIFEST_SOURCE}" "${MANIFEST_DEST}"
fi

echo "Installed: ${MANIFEST_DEST}"
echo ""
echo "Native messaging host binary expected at:"
echo "  /Applications/Pipeline.app/Contents/MacOS/PipelineNativeHost"
echo ""
echo "Done."
