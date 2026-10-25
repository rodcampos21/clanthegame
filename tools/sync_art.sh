#!/usr/bin/env bash
# Rebuild pixel art with claude-pxl and copy the PNGs into the Godot project.
# Usage: PXL=/path/to/claude-pxl tools/sync_art.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PXL="${PXL:-../claude-pxl}"
node "$PXL/bin/pxl.js" build art/clan.px.js --no-preview
mkdir -p assets/sprites
cp art/out/sprites/*.png art/out/anims/*.png art/out/scenes/*.png assets/sprites/
echo "art synced -> assets/sprites"
