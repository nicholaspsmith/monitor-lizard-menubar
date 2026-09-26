#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith

# Build "Monitor Lizard.app" and symlink it into ~/Applications (rebuilds
# propagate; SMAppService accepts a symlink there for Start at Login).
set -euo pipefail

# Menubarn release rule — every push is a release. Arm the pre-push hook in
# every Menubarn repo cloned beside this one (local git config, so a fresh
# clone has none until this runs). StatusItemKit README, "Releases".
RELEASE_KIT="$(cd "$(dirname "$0")/.." && pwd)/StatusItemKit/scripts/release/adopt.sh"
if [ -x "$RELEASE_KIT" ]; then
    "$RELEASE_KIT" --hooks-only || echo "Release hook: adopt.sh failed" >&2
else
    echo "Release hook: StatusItemKit not found beside this repo — clone it and re-run" >&2
fi
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Monitor Lizard.app"

if pgrep -xq BetterDisplay; then
  echo "BetterDisplay is running. Quit it first — two apps on one DDC bus interfere." >&2
  exit 1
fi

"$SRC_DIR/scripts/build-app.sh"
mkdir -p "$HOME/Applications"
ln -sfn "$SRC_DIR/build/$APP_NAME" "$HOME/Applications/$APP_NAME"
echo "Linked $HOME/Applications/$APP_NAME -> $SRC_DIR/build/$APP_NAME"
open "$HOME/Applications/$APP_NAME"

cat <<'EOF'

Monitor Lizard is now running in the menu bar.

  • Drag Brightness / Contrast to drive the external display over DDC.
  • Resolution slider steps through the HiDPI "looks like" sizes; ▸ lists every mode.
  • If a display is flagged as a TV by macOS you will get ONE admin prompt; after
    that, reconnect the display (or reboot) and Night Shift works on it.
  • Optional: menu ▸ Start at Login.
EOF
