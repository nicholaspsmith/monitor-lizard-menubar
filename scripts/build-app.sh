#!/bin/bash
# Build "Monitor Lizard.app" via the shared StatusItemKit bundler.
set -euo pipefail
cd "$(dirname "$0")/.."
exec ../StatusItemKit/scripts/make-app.sh MonitorLizard "Monitor Lizard"
