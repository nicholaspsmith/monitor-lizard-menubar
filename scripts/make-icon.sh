#!/usr/bin/env bash
# docs/mascot.png (square, transparent) → Resources/bundle/AppIcon.icns.
# Without an .icns macOS shows a blank tile (e.g. in Barn's hidden-icons menu).
set -euo pipefail
cd "$(dirname "$0")/.."
src="${1:-docs/mascot.png}"
[ -f "$src" ] || { echo "no mascot at $src" >&2; exit 1; }
set_dir="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$set_dir" Resources/bundle
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$src" --out "$set_dir/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$src" --out "$set_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o Resources/bundle/AppIcon.icns
echo "wrote Resources/bundle/AppIcon.icns"
