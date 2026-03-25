#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SHARED_DIR="$ROOT_DIR/SharedExtensionJS"
CHROME_DIR="$ROOT_DIR/ChromeExtension"
SAFARI_DIR="$ROOT_DIR/Pipeline/PipelineSafariExtension/Resources"

sync_file() {
  src="$1"
  dest="$2"

  if [ ! -f "$src" ]; then
    echo "Missing shared asset: $src" >&2
    exit 1
  fi

  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    return
  fi

  cp "$src" "$dest"
}

sync_file "$SHARED_DIR/content.js" "$CHROME_DIR/content.js"
sync_file "$SHARED_DIR/content.js" "$SAFARI_DIR/content.js"
sync_file "$SHARED_DIR/background.js" "$CHROME_DIR/background.js"
sync_file "$SHARED_DIR/background.js" "$SAFARI_DIR/background.js"
sync_file "$SHARED_DIR/popup.js" "$CHROME_DIR/popup.js"
sync_file "$SHARED_DIR/popup.js" "$SAFARI_DIR/popup.js"
sync_file "$SHARED_DIR/popup.html" "$CHROME_DIR/popup.html"
sync_file "$SHARED_DIR/popup.html" "$SAFARI_DIR/popup.html"
sync_file "$SHARED_DIR/popup.css" "$CHROME_DIR/popup.css"
sync_file "$SHARED_DIR/popup.css" "$SAFARI_DIR/popup.css"
