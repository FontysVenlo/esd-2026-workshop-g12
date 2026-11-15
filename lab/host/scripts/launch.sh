#!/bin/bash
# launch.sh -- runs INSIDE the DinD "host" container.
#
# Creates (or recreates) the vulnerable container for a given level using the
# dangerous flags defined in levels.conf, then leaves it running so the
# orchestrator on the laptop can `docker exec` a shell into it.
#
# Usage: launch.sh <level>
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

source "$DIR/levels.conf"

LEVEL="${1:?usage: launch.sh <level>}"
NAME="level${LEVEL}"

case " $LEVELS " in *" $LEVEL "*) : ;; *) echo "unknown level: $LEVEL" >&2; exit 1;; esac

# Check if the vuln:latest image is already loaded in the host engine.
if ! docker image inspect vuln:latest >/dev/null 2>&1; then
  echo "vuln:latest not loaded in the host engine yet -- run 'lab.sh up' first." >&2
  exit 1
fi

# Per-level host-side setup.
level_setup "$LEVEL"

# Fresh container every time so a level is always in a known-good state.
docker rm -f "$NAME" >/dev/null 2>&1 || true

# shellcheck disable=SC2046
docker run -d --name "$NAME" \
  --user "$(level_user "$LEVEL")" \
  $(level_runargs "$LEVEL") \
  vuln:latest sleep infinity >/dev/null

echo "started $NAME : $(level_title "$LEVEL")"
